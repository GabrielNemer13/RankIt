import XCTest
import SwiftData
@testable import RankIt

/// Integration-level tests for how `LogFlowViewModel.save()` actually
/// persists `rankPosition`, driven through real SwiftData -- not just the
/// pure `RankingEngine` logic already covered by RankingEngineTests.
///
/// What this confirms about the storage layer: insertion is NOT a
/// sparse/gap-based key scheme. `save()` always makes room by shifting
/// every row whose `rankPosition` *value* is >= the target threshold up by
/// exactly one, which keeps the sequence dense (0, 1, 2, ...) after every
/// insertion. The only place an actual numeric gap can appear is deletion
/// (MovieDetailView's remove action), which intentionally does NOT
/// renumber anything else -- that's the "gap-tolerant" part, and it's
/// distinct from insertion, which never relies on or produces gaps.
@MainActor
final class LogFlowRankingIntegrationTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var currentUser: User!

    override func setUpWithError() throws {
        let schema = Schema([
            User.self, Movie.self, LoggedMovie.self, ComparisonEvent.self,
            Watchlist.self, Follow.self, ActivityFeedItem.self, Trailer.self,
            DiscoverInteraction.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(modelContainer)
        currentUser = User(username: "test", displayName: "Test")
        modelContext.insert(currentUser)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
        currentUser = nil
    }

    // MARK: - Helpers

    private enum Choice {
        case newWins
        case existingWins
        case tie
    }

    @discardableResult
    private func log(_ movie: Movie, tier: MovieTier, choices: [Choice]) -> LoggedMovie {
        modelContext.insert(movie)
        let viewModel = LogFlowViewModel(movie: movie, tier: tier, currentUser: currentUser, modelContext: modelContext)
        for choice in choices {
            switch choice {
            case .newWins: viewModel.chooseNew()
            case .existingWins: viewModel.chooseExisting()
            case .tie: viewModel.chooseTie()
            }
        }
        guard let saved = viewModel.save() else {
            XCTFail("save() returned nil -- engine wasn't complete after the given choices")
            return LoggedMovie(userID: currentUser.id, movieID: movie.tmdbID, tier: tier, rankPosition: -999)
        }
        return saved
    }

    private func fetchTier(_ tier: MovieTier) -> [LoggedMovie] {
        let userID = currentUser.id
        let descriptor = FetchDescriptor<LoggedMovie>(predicate: #Predicate<LoggedMovie> { $0.userID == userID })
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { $0.tier == tier }.sorted(by: LoggedMovie.isOrderedForDisplay)
    }

    private func fetchMovie(_ tmdbID: Int) -> Movie {
        let descriptor = FetchDescriptor<Movie>(predicate: #Predicate<Movie> { $0.tmdbID == tmdbID })
        guard let movie = (try? modelContext.fetch(descriptor))?.first else {
            fatalError("expected movie \(tmdbID) to already be cached")
        }
        return movie
    }

    /// Drives (but does not save) a "Change Tier" comparison flow for an
    /// already-logged movie -- mirrors `log(_:tier:choices:)` but goes
    /// through `.reRank(existing:)` instead of `.newLog`. Callers decide
    /// whether to call `.save()`, so this also covers the "cancel mid-flow"
    /// case.
    private func moveToTier(_ loggedMovie: LoggedMovie, newTier: MovieTier, choices: [Choice]) -> LogFlowViewModel {
        let movie = fetchMovie(loggedMovie.movieID)
        let viewModel = LogFlowViewModel(
            movie: movie,
            tier: newTier,
            currentUser: currentUser,
            modelContext: modelContext,
            reRanking: loggedMovie
        )
        for choice in choices {
            switch choice {
            case .newWins: viewModel.chooseNew()
            case .existingWins: viewModel.chooseExisting()
            case .tie: viewModel.chooseTie()
            }
        }
        return viewModel
    }

    // MARK: - Change Tier

    func test_moveToEmptyTier_landsAtPositionZeroWithNoComparisons() {
        let movieA = Movie(tmdbID: 100, title: "A", year: 2000)
        let loggedA = log(movieA, tier: .loved, choices: [])

        let viewModel = moveToTier(loggedA, newTier: .liked, choices: [])
        XCTAssertTrue(viewModel.isComplete, "moving into an empty tier should complete instantly, with no comparisons needed")
        viewModel.save()

        XCTAssertEqual(loggedA.tier, .liked)
        XCTAssertEqual(loggedA.rankPosition, 0)
        XCTAssertTrue(fetchTier(.loved).isEmpty, "the movie should no longer show up in its old tier")
    }

    func test_moveToPopulatedTier_ordersCorrectlyAndLeavesOldTierIntact() {
        let movieX = Movie(tmdbID: 101, title: "X", year: 2000)
        let movieA = Movie(tmdbID: 102, title: "A", year: 2000)
        let movieB = Movie(tmdbID: 103, title: "B", year: 2000)
        let movieC = Movie(tmdbID: 104, title: "C", year: 2000)

        log(movieX, tier: .loved, choices: [])
        // A loses to X -> loved tier is [X, A]
        let loggedA = log(movieA, tier: .loved, choices: [.existingWins])

        log(movieB, tier: .liked, choices: [])
        // C loses to B -> liked tier is [B, C]
        log(movieC, tier: .liked, choices: [.existingWins])

        // Move A into liked: beats C (mid=1), loses to B (mid=0) -> lands
        // between them, same binary-insertion pattern already covered by
        // test_repeatedMiddleInsertions_produceCorrectOrderAndDenseRankValues.
        let viewModel = moveToTier(loggedA, newTier: .liked, choices: [.newWins, .existingWins])
        XCTAssertTrue(viewModel.isComplete)
        viewModel.save()

        let likedTier = fetchTier(.liked)
        XCTAssertEqual(likedTier.map(\.movieID), [movieB.tmdbID, movieA.tmdbID, movieC.tmdbID], "expected display order B, A, C")

        let lovedTier = fetchTier(.loved)
        XCTAssertEqual(lovedTier.map(\.movieID), [movieX.tmdbID], "loved tier should only contain the movie that stayed")
        XCTAssertEqual(lovedTier.first?.rankPosition, 0, "the remaining row's rankPosition is untouched -- same gap-tolerant convention as deleting a LoggedMovie outright")
    }

    func test_cancelMidFlow_leavesMovieInOriginalTierAndPosition() {
        let movieX = Movie(tmdbID: 105, title: "X", year: 2000)
        let movieA = Movie(tmdbID: 106, title: "A", year: 2000)
        let movieB = Movie(tmdbID: 107, title: "B", year: 2000)

        log(movieX, tier: .loved, choices: [])
        // loved tier is [X, A]
        let loggedA = log(movieA, tier: .loved, choices: [.existingWins])
        log(movieB, tier: .liked, choices: [])

        let originalTier = loggedA.tier
        let originalRankPosition = loggedA.rankPosition

        // Drive a comparison but never call save() -- simulating the user
        // backing out of the "Change Tier" flow before confirming.
        _ = moveToTier(loggedA, newTier: .liked, choices: [.newWins])

        XCTAssertEqual(loggedA.tier, originalTier, "cancelling mid-flow must not touch the movie's tier")
        XCTAssertEqual(loggedA.rankPosition, originalRankPosition, "cancelling mid-flow must not touch the movie's rankPosition")
        XCTAssertEqual(fetchTier(.loved).map(\.movieID), [movieX.tmdbID, movieA.tmdbID], "the old tier is untouched until save() is actually called")
    }

    // MARK: - Repeated middle insertions

    func test_repeatedMiddleInsertions_produceCorrectOrderAndDenseRankValues() {
        let movieA = Movie(tmdbID: 1, title: "A", year: 2000)
        let movieB = Movie(tmdbID: 2, title: "B", year: 2000)
        let movieC = Movie(tmdbID: 3, title: "C", year: 2000)
        let movieD = Movie(tmdbID: 4, title: "D", year: 2000)

        log(movieA, tier: .loved, choices: [])
        // B beats A -> [B, A]
        log(movieB, tier: .loved, choices: [.newWins])
        // C beats A(mid=1), loses to B(mid=0) -> lands in the middle: [B, C, A]
        log(movieC, tier: .loved, choices: [.newWins, .existingWins])
        // D loses to C(mid=1), beats A(mid=2) -> lands in the *new* middle: [B, C, D, A]
        log(movieD, tier: .loved, choices: [.existingWins, .newWins])

        let tier = fetchTier(.loved)
        XCTAssertEqual(tier.map(\.movieID), [2, 3, 4, 1], "expected display order B, C, D, A")
        XCTAssertEqual(tier.map(\.rankPosition), [0, 1, 2, 3], "rankPosition should stay dense after repeated middle insertions")
    }

    // MARK: - savedLoggedMovie (drives ComparisonView's auto-navigate-to-detail)

    func test_save_newLog_exposesSavedLoggedMovie() {
        let movie = Movie(tmdbID: 200, title: "A", year: 2000)
        modelContext.insert(movie)
        let viewModel = LogFlowViewModel(movie: movie, tier: .loved, currentUser: currentUser, modelContext: modelContext)

        let saved = viewModel.save()

        XCTAssertNotNil(saved)
        XCTAssertTrue(viewModel.savedLoggedMovie === saved, "savedLoggedMovie should be the exact row save() returned")
    }

    func test_save_reRank_exposesSavedLoggedMovieAsTheExistingRow() {
        let movie = Movie(tmdbID: 201, title: "A", year: 2000)
        let loggedA = log(movie, tier: .loved, choices: [])

        let viewModel = moveToTier(loggedA, newTier: .liked, choices: [])
        viewModel.save()

        XCTAssertTrue(viewModel.savedLoggedMovie === loggedA, "re-ranking should expose the same (mutated) row, not a new one")
    }

    func test_savedLoggedMovie_staysNilBeforeSaveIsCalled() {
        let movie = Movie(tmdbID: 202, title: "A", year: 2000)
        modelContext.insert(movie)
        let viewModel = LogFlowViewModel(movie: movie, tier: .loved, currentUser: currentUser, modelContext: modelContext)

        XCTAssertNil(viewModel.savedLoggedMovie)
    }

    // MARK: - Ties survive a nearby non-tied insertion

    func test_tieGroupStaysIntactAndOrderedByWatchedDate_afterNearbyInsertion() {
        let movieX = Movie(tmdbID: 10, title: "X", year: 2000)
        let movieY = Movie(tmdbID: 11, title: "Y", year: 2000)
        let movieZ = Movie(tmdbID: 12, title: "Z", year: 2000)

        let loggedX = log(movieX, tier: .liked, choices: [])
        let loggedY = log(movieY, tier: .liked, choices: [.tie]) // Y ties X

        // Pin down watchedDate explicitly rather than relying on real
        // wall-clock ordering between two fast successive saves.
        loggedX.watchedDate = Date(timeIntervalSince1970: 1_000)
        loggedY.watchedDate = Date(timeIntervalSince1970: 2_000)

        // Z decisively beats the whole tied group (needs two comparisons
        // for a 2-item tier: mid=1 then mid=0).
        log(movieZ, tier: .liked, choices: [.newWins, .newWins])

        let tier = fetchTier(.liked)
        XCTAssertEqual(tier.map(\.movieID), [12, 11, 10], "expected Z first, then Y (more recent), then X (older)")
        XCTAssertEqual(tier[0].rankPosition, 0)
        XCTAssertEqual(tier[1].rankPosition, tier[2].rankPosition, "X and Y should still share a rankPosition")
        XCTAssertEqual(tier[1].rankPosition, 1, "the tied pair should have shifted together, from 0 to 1")
    }
}
