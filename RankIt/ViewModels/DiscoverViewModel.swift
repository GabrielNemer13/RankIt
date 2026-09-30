import Foundation
import SwiftData
import Observation

/// A movie paired with the one trailer to show for it in the feed.
struct DiscoverCandidate: Identifiable, Equatable {
    let movie: Movie
    let trailer: Trailer?
    var id: Int { movie.tmdbID }
}

@MainActor
@Observable
final class DiscoverViewModel {
    private(set) var candidates: [DiscoverCandidate] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    /// Movie IDs currently on the signed-in user's watchlist, refreshed on
    /// every `load()` so a card renders already-filled on first appearance
    /// -- including re-entering the tab -- rather than starting empty and
    /// only filling in after a tap.
    private(set) var watchlistedMovieIDs: Set<Int> = []
    var selectedGenre: String?

    private let catalogService: any MovieCatalogServicing
    private let currentUser: User
    private let modelContext: ModelContext
    private var nextPage = 1
    private var hasMorePages = true

    init(catalogService: any MovieCatalogServicing, currentUser: User, modelContext: ModelContext) {
        self.catalogService = catalogService
        self.currentUser = currentUser
        self.modelContext = modelContext
    }

    /// Genres present in the current candidate set, for the filter menu.
    var availableGenres: [String] {
        Array(Set(candidates.flatMap(\.movie.genres))).sorted()
    }

    var visibleCandidates: [DiscoverCandidate] {
        guard let selectedGenre else { return candidates }
        return candidates.filter { $0.movie.genres.contains(selectedGenre) }
    }

    func loadIfNeeded() async {
        guard candidates.isEmpty, !isLoading else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        candidates = []
        nextPage = 1
        hasMorePages = true
        watchlistedMovieIDs = fetchWatchlistedMovieIDs()
        defer { isLoading = false }
        await loadPage()
    }

    /// Called by the view as the user scrolls near the end of the feed.
    /// `candidate` is the row currently coming into view; this only fetches
    /// more once the user is within the last few cards, so a single scroll
    /// gesture doesn't trigger several redundant loads.
    func loadMoreIfNeeded(currentCandidate candidate: DiscoverCandidate) {
        guard hasMorePages, !isLoading, !isLoadingMore else { return }
        guard let index = visibleCandidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        guard index >= visibleCandidates.count - 3 else { return }
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard hasMorePages, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await loadPage()
    }

    /// Fetches `nextPage`, builds candidates for it, and appends them —
    /// used by both the initial load and subsequent "load more" calls.
    /// On failure: if this was the very first page (`candidates` still
    /// empty), surface `errorMessage` for the empty/error state; on a later
    /// page, fail silently and just stop paginating, so a transient error
    /// deep into the feed doesn't blow away everything already shown.
    private func loadPage() async {
        do {
            // TODO: once trending is exhausted (or as a richer fallback),
            // broaden to another TMDb source — e.g. `discover/movie`
            // weighted toward genres the user ranks highly — and replace
            // this raw trending order with a real recommendation ranking.
            let page = try await catalogService.trending(page: nextPage)
            hasMorePages = page.hasMorePages
            nextPage = page.page + 1

            let loggedMovieIDs = Set(fetchLoggedMovieIDs())
            let existingIDs = Set(candidates.map(\.movie.tmdbID))
            let unseen = page.movies.filter { !loggedMovieIDs.contains($0.tmdbID) && !existingIDs.contains($0.tmdbID) }

            var built: [DiscoverCandidate] = []
            for movie in unseen {
                let trailers = (try? await catalogService.officialTrailers(movieID: movie.tmdbID)) ?? []
                let trailer = trailers.first(where: { $0.type == .trailer }) ?? trailers.first
                built.append(DiscoverCandidate(movie: movie, trailer: trailer))
            }
            candidates += built
        } catch {
            hasMorePages = false
            if candidates.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Adds or removes the candidate's movie from the Watchlist, toggling
    /// on the current state in `watchlistedMovieIDs` -- a second tap while
    /// already watchlisted removes it, rather than being a no-op. That
    /// matches the button's own filled/empty affordance (it looks like a
    /// toggle, so it should behave like one) and gives the user a way to
    /// undo an accidental tap without leaving Discover.
    ///
    /// Only the *addition* records a `DiscoverInteraction` -- removing here
    /// is corrective/undo behavior, not a new discovery signal worth
    /// logging, matching how deleting a Library/Watchlist row elsewhere in
    /// the app doesn't log an activity event either.
    func toggleWatchlist(for candidate: DiscoverCandidate) {
        let movieID = candidate.movie.tmdbID
        if watchlistedMovieIDs.contains(movieID) {
            removeFromWatchlist(movieID: movieID)
            watchlistedMovieIDs.remove(movieID)
        } else {
            addToWatchlist(candidate: candidate)
            watchlistedMovieIDs.insert(movieID)
        }
        try? modelContext.save()
    }

    /// Called once a movie has been ranked via the "Rank it" sheet's
    /// tier-picker/comparison flow (the `LogFlowViewModel` save itself
    /// already wrote the `LoggedMovie` -- this is Discover's own
    /// bookkeeping on top of that). Removes it from the feed immediately,
    /// rather than waiting for the next `load()` to apply the
    /// already-logged filter, and logs a `.logged` `DiscoverInteraction`
    /// for parity with how Watchlist/Skip are recorded.
    ///
    /// Also clears any Watchlist entry: once a movie has a real rank in
    /// the Library, leaving it in "want to watch" would be stale --
    /// Watchlist is for movies not yet seen.
    func markRanked(_ candidate: DiscoverCandidate) {
        candidates.removeAll { $0.id == candidate.id }
        let movieID = candidate.movie.tmdbID
        modelContext.insert(DiscoverInteraction(userID: currentUser.id, movieID: movieID, action: .logged))
        if watchlistedMovieIDs.contains(movieID) {
            removeFromWatchlist(movieID: movieID)
            watchlistedMovieIDs.remove(movieID)
        }
        try? modelContext.save()
    }

    private func addToWatchlist(candidate: DiscoverCandidate) {
        let interaction = DiscoverInteraction(userID: currentUser.id, movieID: candidate.movie.tmdbID, action: .watchlisted)
        modelContext.insert(interaction)
        // Candidates from trending() are never persisted on their own —
        // cache the Movie now so Watchlist (and anything else joining by
        // tmdbID) can actually resolve it later, instead of just storing
        // a dangling movieID.
        upsertMovie(candidate.movie)
        let watchlistEntry = Watchlist(userID: currentUser.id, movieID: candidate.movie.tmdbID)
        modelContext.insert(watchlistEntry)
        modelContext.insert(ActivityFeedItem(userID: currentUser.id, type: .watchlisted, refID: watchlistEntry.id))
    }

    private func removeFromWatchlist(movieID: Int) {
        let userID = currentUser.id
        let descriptor = FetchDescriptor<Watchlist>(
            predicate: #Predicate<Watchlist> { $0.userID == userID && $0.movieID == movieID }
        )
        for entry in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(entry)
        }
    }

    private func fetchWatchlistedMovieIDs() -> Set<Int> {
        let userID = currentUser.id
        let descriptor = FetchDescriptor<Watchlist>(predicate: #Predicate<Watchlist> { $0.userID == userID })
        return Set(((try? modelContext.fetch(descriptor)) ?? []).map(\.movieID))
    }

    @discardableResult
    private func upsertMovie(_ movie: Movie) -> Movie {
        let tmdbID = movie.tmdbID
        let descriptor = FetchDescriptor<Movie>(predicate: #Predicate<Movie> { $0.tmdbID == tmdbID })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            return existing
        }
        modelContext.insert(movie)
        return movie
    }

    private func fetchLoggedMovieIDs() -> [Int] {
        let userID = currentUser.id
        let descriptor = FetchDescriptor<LoggedMovie>(predicate: #Predicate<LoggedMovie> { $0.userID == userID })
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.movieID)
    }
}
