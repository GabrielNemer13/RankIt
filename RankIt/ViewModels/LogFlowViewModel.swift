import Foundation
import SwiftData
import Observation

/// A tier entry paired with the display title `RankingEngine` needs to show
/// the user, without making the engine itself know anything about `Movie`.
struct RankableEntry: Identifiable {
    let loggedMovie: LoggedMovie
    let title: String
    var id: UUID { loggedMovie.id }
}

/// Drives the comparison screen: wraps a `RankingEngine<RankableEntry>` for
/// the chosen tier and, once complete, either writes a new `LoggedMovie`
/// (`.newLog`) or repositions an existing one (`.reRank`) with the correct
/// `rankPosition` — shifting existing items down for a normal insertion, or
/// reusing the tied item's `rankPosition` for a tie. Either mode also
/// records each individual comparison as a `ComparisonEvent`.
///
/// `.reRank` also covers moving a movie to a *different* tier (see
/// `MovieDetailView`'s "Change Tier" action): passing a `tier` that differs
/// from `existing.tier` naturally excludes `existing` from the fetched
/// comparison pool (it simply isn't in that tier yet), and `save()`
/// reassigns `existing.tier` to the new one. The old tier's remaining rows
/// are left untouched -- same gap-tolerant convention as deleting a
/// `LoggedMovie` outright (see `MovieDetailView.performRemove`) -- so
/// nothing needs to shift there. Nothing is written until `save()` runs, so
/// backing out mid-comparison leaves the movie in its original tier and
/// position.
@MainActor
@Observable
final class LogFlowViewModel {
    private enum Mode {
        case newLog
        // `originalTier` is captured once at init, separately from
        // `existing.tier` -- `save()` mutates `existing.tier` in place, so
        // reading it live after saving would always equal `tier` and hide
        // that this was ever a tier change.
        case reRank(existing: LoggedMovie, originalTier: MovieTier)
    }

    let movie: Movie
    let tier: MovieTier

    private(set) var currentComparisonTitle: String?
    private(set) var isComplete: Bool
    private(set) var canUndo: Bool
    private(set) var isSaved = false

    private let mode: Mode
    private let engine: RankingEngine<RankableEntry>
    private let currentUser: User
    private let modelContext: ModelContext
    private var comparisonEventStack: [ComparisonEvent] = []

    /// - Parameter reRanking: pass the movie's existing `LoggedMovie` to
    ///   re-run comparisons and reposition it, instead of logging a new one.
    ///   Its own row is excluded from the tier it's compared against.
    init(movie: Movie, tier: MovieTier, currentUser: User, modelContext: ModelContext, reRanking existing: LoggedMovie? = nil) {
        self.movie = movie
        self.tier = tier
        self.currentUser = currentUser
        self.modelContext = modelContext
        self.mode = existing.map { Mode.reRank(existing: $0, originalTier: $0.tier) } ?? .newLog

        // Fetch by userID only and filter the tier client-side: compound
        // predicates that also compare a stored enum property have proven
        // unreliable with SwiftData's predicate translator (silently throws,
        // swallowed by `try?`, yielding an incorrectly-empty tier).
        let userID = currentUser.id
        let descriptor = FetchDescriptor<LoggedMovie>(
            predicate: #Predicate<LoggedMovie> { $0.userID == userID }
        )
        var existingRows = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.tier == tier }
        if let existing {
            existingRows.removeAll { $0.id == existing.id }
        }
        let sortedExisting = existingRows.sorted(by: LoggedMovie.isOrderedForDisplay)
        let entries = sortedExisting.map { logged in
            RankableEntry(
                loggedMovie: logged,
                title: LogFlowViewModel.movieTitle(forTmdbID: logged.movieID, in: modelContext) ?? "Unknown movie"
            )
        }

        let engine = RankingEngine(existingTier: entries)
        self.engine = engine
        currentComparisonTitle = engine.currentComparisonItem?.title
        isComplete = engine.isComplete
        canUndo = engine.canUndo
    }

    var isReRanking: Bool {
        if case .reRank = mode { return true }
        return false
    }

    /// True when re-ranking into a tier different from the movie's original
    /// one (a "Change Tier" move), as opposed to a same-tier re-rank.
    var isTierChange: Bool {
        if case .reRank(_, let originalTier) = mode { return originalTier != tier }
        return false
    }

    /// Non-nil only once `isComplete` is true; tells the caller whether the
    /// result was a normal insertion or a tie.
    var completion: RankingEngine<RankableEntry>.Completion? {
        engine.completion
    }

    var tiedMovieTitle: String? {
        guard case .tie(let index) = engine.completion else { return nil }
        return engine.items[index].title
    }

    func chooseNew() {
        recordComparisonEvent(winner: .new)
        engine.recordComparison(winner: .new)
        refresh()
    }

    func chooseExisting() {
        recordComparisonEvent(winner: .existing)
        engine.recordComparison(winner: .existing)
        refresh()
    }

    func chooseTie() {
        recordComparisonEvent(winner: .tie)
        engine.recordComparison(winner: .tie)
        refresh()
    }

    func undo() {
        engine.undoLastComparison()
        if let lastEvent = comparisonEventStack.popLast() {
            // Not persisted yet (no modelContext.save() has run since it was
            // inserted), so this cleanly erases the retracted decision
            // rather than leaving a ghost entry in comparison history.
            modelContext.delete(lastEvent)
        }
        refresh()
    }

    private func refresh() {
        currentComparisonTitle = engine.currentComparisonItem?.title
        isComplete = engine.isComplete
        canUndo = engine.canUndo
    }

    /// Records the comparison the user just answered as a `ComparisonEvent`
    /// -- called *before* `engine.recordComparison`, while
    /// `currentComparisonItem` still refers to the item just answered.
    private func recordComparisonEvent(winner: RankingEngine<RankableEntry>.Winner) {
        guard let opponent = engine.currentComparisonItem else { return }
        let opponentMovieID = opponent.loggedMovie.movieID
        let winnerMovieID: Int?
        switch winner {
        case .new: winnerMovieID = movie.tmdbID
        case .existing: winnerMovieID = opponentMovieID
        case .tie: winnerMovieID = nil
        }
        let event = ComparisonEvent(
            userID: currentUser.id,
            movieAID: movie.tmdbID,
            movieBID: opponentMovieID,
            winnerID: winnerMovieID,
            tier: tier
        )
        modelContext.insert(event)
        comparisonEventStack.append(event)
    }

    /// Writes the result: a new `LoggedMovie` for `.newLog`, or an updated
    /// `rankPosition`/`watchedDate` on the existing one for `.reRank`. No-op
    /// (returns `nil`) if comparisons aren't finished yet.
    @discardableResult
    func save() -> LoggedMovie? {
        guard let completion = engine.completion else { return nil }
        let rankPosition = resolvedRankPosition(for: completion)

        switch mode {
        case .newLog:
            let cachedMovie = LogFlowViewModel.upsertMovie(movie, in: modelContext)
            let userID = currentUser.id
            let movieID = cachedMovie.tmdbID
            let priorLogsForMovie = (try? modelContext.fetch(
                FetchDescriptor<LoggedMovie>(
                    predicate: #Predicate<LoggedMovie> { $0.userID == userID && $0.movieID == movieID }
                )
            )) ?? []

            let newLog = LoggedMovie(
                userID: currentUser.id,
                movieID: cachedMovie.tmdbID,
                tier: tier,
                rankPosition: rankPosition,
                isRewatch: !priorLogsForMovie.isEmpty
            )
            modelContext.insert(newLog)
            modelContext.insert(ActivityFeedItem(userID: currentUser.id, type: .logged, refID: newLog.id))
            try? modelContext.save()
            isSaved = true
            return newLog

        case .reRank(let existingLog, _):
            // Reassigning `tier` here (not sooner) is what makes this a
            // "move": the row drops out of its old tier's queries the
            // instant this runs, and not before. The old tier's other rows
            // are left as-is -- same gap-tolerant convention as deletion.
            existingLog.tier = tier
            existingLog.rankPosition = rankPosition
            existingLog.watchedDate = .now
            try? modelContext.save()
            isSaved = true
            return existingLog
        }
    }

    /// Shared by both modes: translates the engine's completion into the
    /// `rankPosition` the item should end up at, shifting neighbors by value
    /// (not array index) so an existing tied group moves together rather
    /// than splitting apart.
    private func resolvedRankPosition(for completion: RankingEngine<RankableEntry>.Completion) -> Int {
        switch completion {
        case .insert(let arrayIndex):
            if arrayIndex < engine.items.count {
                let threshold = engine.items[arrayIndex].loggedMovie.rankPosition
                for entry in engine.items where entry.loggedMovie.rankPosition >= threshold {
                    entry.loggedMovie.rankPosition += 1
                }
                return threshold
            } else {
                return (engine.items.last?.loggedMovie.rankPosition ?? -1) + 1
            }
        case .tie(let tiedIndex):
            return engine.items[tiedIndex].loggedMovie.rankPosition
        }
    }

    private static func movieTitle(forTmdbID tmdbID: Int, in context: ModelContext) -> String? {
        let descriptor = FetchDescriptor<Movie>(predicate: #Predicate<Movie> { $0.tmdbID == tmdbID })
        return (try? context.fetch(descriptor))?.first?.title
    }

    private static func upsertMovie(_ movie: Movie, in context: ModelContext) -> Movie {
        let tmdbID = movie.tmdbID
        let descriptor = FetchDescriptor<Movie>(predicate: #Predicate<Movie> { $0.tmdbID == tmdbID })
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        context.insert(movie)
        return movie
    }
}
