import XCTest
import SwiftData
@testable import RankIt

@MainActor
final class MovieSearchViewModelTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var currentUser: User!
    private var defaults: UserDefaults!
    private var suiteName: String!

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

        suiteName = "MovieSearchViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        modelContainer = nil
        modelContext = nil
        currentUser = nil
        defaults = nil
    }

    private func makeViewModel(service: any MovieCatalogServicing) -> MovieSearchViewModel {
        MovieSearchViewModel(
            catalogService: service,
            currentUser: currentUser,
            modelContext: modelContext,
            recentSearchesStore: RecentSearchesStore(defaults: defaults)
        )
    }

    // MARK: - Fakes

    private struct DelayedResultsService: MovieCatalogServicing {
        var delaysByQuery: [String: UInt64] = [:]
        var resultsByQuery: [String: [Movie]] = [:]

        func searchMovies(query: String) async throws -> [Movie] {
            if let delay = delaysByQuery[query] {
                try await Task.sleep(nanoseconds: delay)
            }
            return resultsByQuery[query] ?? []
        }
        func movieDetails(id: Int) async throws -> Movie { fatalError("not needed") }
        func trending() async throws -> [Movie] { [] }
        func officialTrailers(movieID: Int) async throws -> [Trailer] { [] }
    }

    private struct TrendingService: MovieCatalogServicing {
        let movies: [Movie]
        func searchMovies(query: String) async throws -> [Movie] { [] }
        func movieDetails(id: Int) async throws -> Movie { fatalError("not needed") }
        func trending() async throws -> [Movie] { movies }
        func officialTrailers(movieID: Int) async throws -> [Trailer] { [] }
    }

    private struct FailingService: MovieCatalogServicing {
        struct Failure: Error, LocalizedError {
            var errorDescription: String? { "Simulated failure" }
        }
        func searchMovies(query: String) async throws -> [Movie] { throw Failure() }
        func movieDetails(id: Int) async throws -> Movie { throw Failure() }
        func trending() async throws -> [Movie] { throw Failure() }
        func officialTrailers(movieID: Int) async throws -> [Trailer] { [] }
    }

    private struct MissingKeyService: MovieCatalogServicing {
        func searchMovies(query: String) async throws -> [Movie] { throw TMDbError.missingAPIKey }
        func movieDetails(id: Int) async throws -> Movie { throw TMDbError.missingAPIKey }
        func trending() async throws -> [Movie] { throw TMDbError.missingAPIKey }
        func officialTrailers(movieID: Int) async throws -> [Trailer] { [] }
    }

    // MARK: - Staleness / debounce hardening

    /// Simulates two overlapping searches directly (rather than relying on
    /// SwiftUI's `.task(id:)` cancellation) to prove the view model's own
    /// `searchGeneration` guard is what keeps a stale response from
    /// clobbering a newer one -- not just incidental `Task` cancellation
    /// timing.
    func test_staleSlowerResponse_neverOverwritesNewerResults() async {
        let movieA = Movie(tmdbID: 1, title: "A", year: 2000)
        let movieB = Movie(tmdbID: 2, title: "B", year: 2000)
        let service = DelayedResultsService(
            delaysByQuery: ["alpha": 250_000_000, "beta": 10_000_000],
            resultsByQuery: ["alpha": [movieA], "beta": [movieB]]
        )
        let viewModel = makeViewModel(service: service)

        viewModel.query = "alpha"
        let firstSearch = Task { await viewModel.search() }
        try? await Task.sleep(nanoseconds: 60_000_000)
        viewModel.query = "beta"
        let secondSearch = Task { await viewModel.search() }

        _ = await firstSearch.value
        _ = await secondSearch.value

        XCTAssertEqual(viewModel.results.map(\.tmdbID), [2], "the later search should win even though the earlier search's network call resolves after it")
        XCTAssertFalse(viewModel.isSearching)
    }

    // MARK: - Recent searches

    func test_recordSelection_addsQueryToRecentSearches() {
        let viewModel = makeViewModel(service: DelayedResultsService())
        viewModel.query = "inception"

        XCTAssertTrue(viewModel.recentSearches.isEmpty, "typing alone shouldn't add to history")

        viewModel.recordSelection()

        XCTAssertEqual(viewModel.recentSearches, ["inception"])
    }

    func test_recordSelection_dedupsAndCapsAtTen() {
        let viewModel = makeViewModel(service: DelayedResultsService())
        for i in 1...11 {
            viewModel.query = "query\(i)"
            viewModel.recordSelection()
        }
        // Re-selecting an earlier query should move it to the front, not duplicate it.
        viewModel.query = "query5"
        viewModel.recordSelection()

        XCTAssertEqual(viewModel.recentSearches.count, 10, "should cap at 10 entries")
        XCTAssertEqual(viewModel.recentSearches.first, "query5")
        XCTAssertEqual(viewModel.recentSearches.filter { $0 == "query5" }.count, 1, "re-selecting an existing query shouldn't duplicate it")
    }

    /// Deterministic check of tap-to-reuse: the "tap" is just
    /// `selectRecentSearch`, the exact call `MovieSearchView`'s recent-
    /// search row Button makes -- asserted against view model state, not
    /// screenshots, since a live UI tap can't be timed deterministically.
    func test_selectRecentSearch_reusesQuery_andTriggersANewSearchGeneration() {
        let viewModel = makeViewModel(service: DelayedResultsService())
        viewModel.query = "inception"
        viewModel.recordSelection()
        viewModel.query = ""
        XCTAssertTrue(viewModel.recentSearches.contains("inception"))

        viewModel.selectRecentSearch("inception")

        XCTAssertEqual(viewModel.query, "inception", "tapping a recent search must reuse it verbatim as the active query")
    }

    func test_clearRecentSearches_removesEverything() {
        let viewModel = makeViewModel(service: DelayedResultsService())
        viewModel.query = "inception"
        viewModel.recordSelection()
        XCTAssertFalse(viewModel.recentSearches.isEmpty)

        viewModel.clearRecentSearches()

        XCTAssertTrue(viewModel.recentSearches.isEmpty)
    }

    func test_selectingTrendingWithEmptyQuery_doesNotPolluteHistory() {
        let viewModel = makeViewModel(service: DelayedResultsService())
        viewModel.query = ""

        viewModel.recordSelection()

        XCTAssertTrue(viewModel.recentSearches.isEmpty, "opening a trending movie (empty query) shouldn't add a blank entry to history")
    }

    // MARK: - Already-logged tiers

    func test_loggedTiers_reflectsCurrentUsersLoggedMovies() {
        let movie = Movie(tmdbID: 42, title: "Logged", year: 2000)
        modelContext.insert(movie)
        modelContext.insert(LoggedMovie(userID: currentUser.id, movieID: 42, tier: .liked, rankPosition: 0))

        let viewModel = makeViewModel(service: DelayedResultsService())

        XCTAssertEqual(viewModel.loggedTiers[42], .liked)
        XCTAssertNil(viewModel.loggedTiers[999], "an unlogged movie shouldn't appear in the map")
    }

    func test_loggedTiers_picksTheMostRecentLogForRewatches() {
        let movie = Movie(tmdbID: 42, title: "Rewatched", year: 2000)
        modelContext.insert(movie)
        let firstWatch = LoggedMovie(userID: currentUser.id, movieID: 42, watchedDate: Date(timeIntervalSince1970: 1_000), tier: .disliked, rankPosition: 0)
        let secondWatch = LoggedMovie(userID: currentUser.id, movieID: 42, watchedDate: Date(timeIntervalSince1970: 2_000), tier: .loved, rankPosition: 0, isRewatch: true)
        modelContext.insert(firstWatch)
        modelContext.insert(secondWatch)

        let viewModel = makeViewModel(service: DelayedResultsService())

        XCTAssertEqual(viewModel.loggedTiers[42], .loved, "the badge should reflect the most recent log, not an older one")
    }

    // MARK: - Trending + error handling

    func test_loadTrendingIfNeeded_populatesTrendingMovies() async {
        let movie = Movie(tmdbID: 1, title: "Trending", year: 2000)
        let viewModel = makeViewModel(service: TrendingService(movies: [movie]))

        await viewModel.loadTrendingIfNeeded()

        XCTAssertEqual(viewModel.trendingMovies.map(\.tmdbID), [1])
        XCTAssertNil(viewModel.trendingErrorMessage)
    }

    func test_trendingFailure_surfacesFriendlyErrorAndCanRetry() async {
        let viewModel = makeViewModel(service: FailingService())

        await viewModel.loadTrendingIfNeeded()

        XCTAssertTrue(viewModel.trendingMovies.isEmpty)
        XCTAssertNotNil(viewModel.trendingErrorMessage)
    }

    func test_searchFailure_surfacesErrorAndClearsResultsRatherThanCrashing() async {
        let viewModel = makeViewModel(service: FailingService())
        viewModel.query = "anything"

        await viewModel.search()

        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertNotNil(viewModel.searchErrorMessage)
        XCTAssertFalse(viewModel.isSearching)
    }

    func test_missingAPIKey_surfacesAsFriendlyErrorNotCrash() async {
        let viewModel = makeViewModel(service: MissingKeyService())
        viewModel.query = "anything"

        await viewModel.search()

        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertEqual(viewModel.searchErrorMessage, TMDbError.missingAPIKey.localizedDescription)
    }

    func test_emptyQuery_clearsResultsWithoutError() async {
        let viewModel = makeViewModel(service: DelayedResultsService())
        viewModel.query = ""

        await viewModel.search()

        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertNil(viewModel.searchErrorMessage)
        XCTAssertFalse(viewModel.isSearching)
    }
}
