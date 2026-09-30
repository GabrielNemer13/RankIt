import XCTest
import SwiftData
@testable import RankIt

@MainActor
final class DiscoverViewModelTests: XCTestCase {
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

    private func makeViewModel(service: any MovieCatalogServicing) -> DiscoverViewModel {
        DiscoverViewModel(catalogService: service, currentUser: currentUser, modelContext: modelContext)
    }

    // MARK: - Fakes

    private struct PagedTrendingService: MovieCatalogServicing {
        let moviesByPage: [Int: [Movie]]
        let totalPages: Int
        var trailersByMovieID: [Int: [Trailer]] = [:]

        func searchMovies(query: String, page: Int) async throws -> MoviePage { .empty }
        func movieDetails(id: Int) async throws -> Movie { fatalError("not needed") }
        func trending(page: Int) async throws -> MoviePage {
            MoviePage(movies: moviesByPage[page] ?? [], page: page, totalPages: totalPages)
        }
        func officialTrailers(movieID: Int) async throws -> [Trailer] {
            trailersByMovieID[movieID] ?? []
        }
    }

    private struct FailingAfterFirstPageService: MovieCatalogServicing {
        let firstPage: [Movie]
        struct Failure: Error, LocalizedError {
            var errorDescription: String? { "Simulated failure" }
        }
        func searchMovies(query: String, page: Int) async throws -> MoviePage { .empty }
        func movieDetails(id: Int) async throws -> Movie { fatalError("not needed") }
        func trending(page: Int) async throws -> MoviePage {
            if page == 1 {
                return MoviePage(movies: firstPage, page: 1, totalPages: 2)
            }
            throw Failure()
        }
        func officialTrailers(movieID: Int) async throws -> [Trailer] { [] }
    }

    private struct AlwaysFailingService: MovieCatalogServicing {
        struct Failure: Error, LocalizedError {
            var errorDescription: String? { "Simulated failure" }
        }
        func searchMovies(query: String, page: Int) async throws -> MoviePage { throw Failure() }
        func movieDetails(id: Int) async throws -> Movie { throw Failure() }
        func trending(page: Int) async throws -> MoviePage { throw Failure() }
        func officialTrailers(movieID: Int) async throws -> [Trailer] { [] }
    }

    // MARK: - Initial load

    func test_load_populatesCandidatesFromFirstPage() async {
        let movie = Movie(tmdbID: 1, title: "One", year: 2000)
        let service = PagedTrendingService(moviesByPage: [1: [movie]], totalPages: 1)
        let viewModel = makeViewModel(service: service)

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.candidates.map(\.id), [1])
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_load_excludesAlreadyLoggedMovies() async {
        let logged = Movie(tmdbID: 1, title: "Logged", year: 2000)
        let unseen = Movie(tmdbID: 2, title: "Unseen", year: 2000)
        modelContext.insert(logged)
        modelContext.insert(LoggedMovie(userID: currentUser.id, movieID: 1, tier: .loved, rankPosition: 0))
        let service = PagedTrendingService(moviesByPage: [1: [logged, unseen]], totalPages: 1)
        let viewModel = makeViewModel(service: service)

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.candidates.map(\.id), [2])
    }

    func test_load_failure_surfacesErrorMessage() async {
        let viewModel = makeViewModel(service: AlwaysFailingService())

        await viewModel.loadIfNeeded()

        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Pagination

    func test_loadMoreIfNeeded_nearEndOfFeed_appendsNextPage() async {
        let page1 = [Movie(tmdbID: 1, title: "One", year: 2000), Movie(tmdbID: 2, title: "Two", year: 2000)]
        let page2 = [Movie(tmdbID: 3, title: "Three", year: 2000)]
        let service = PagedTrendingService(moviesByPage: [1: page1, 2: page2], totalPages: 2)
        let viewModel = makeViewModel(service: service)

        await viewModel.loadIfNeeded()
        XCTAssertEqual(viewModel.candidates.map(\.id), [1, 2])

        viewModel.loadMoreIfNeeded(currentCandidate: viewModel.candidates[1])
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(viewModel.candidates.map(\.id), [1, 2, 3], "scrolling near the end of the feed should load and append the next page")
    }

    /// A transient failure fetching a *later* page shouldn't wipe out
    /// candidates already on screen -- only the very first page's failure
    /// should surface as a blocking error state (see `load_failure_...`).
    func test_loadMoreIfNeeded_laterPageFails_keepsExistingCandidates() async {
        let page1 = [Movie(tmdbID: 1, title: "One", year: 2000)]
        let service = FailingAfterFirstPageService(firstPage: page1)
        let viewModel = makeViewModel(service: service)

        await viewModel.loadIfNeeded()
        XCTAssertEqual(viewModel.candidates.map(\.id), [1])

        viewModel.loadMoreIfNeeded(currentCandidate: viewModel.candidates[0])
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(viewModel.candidates.map(\.id), [1], "existing candidates must survive a later page's failure")
        XCTAssertNil(viewModel.errorMessage, "a later-page failure shouldn't retroactively show the blocking error state")
    }

    // MARK: - Genre filter

    func test_visibleCandidates_filtersBySelectedGenre() async {
        let action = Movie(tmdbID: 1, title: "Action", year: 2000, genres: ["Action"])
        let comedy = Movie(tmdbID: 2, title: "Comedy", year: 2000, genres: ["Comedy"])
        let service = PagedTrendingService(moviesByPage: [1: [action, comedy]], totalPages: 1)
        let viewModel = makeViewModel(service: service)

        await viewModel.loadIfNeeded()
        viewModel.selectedGenre = "Comedy"

        XCTAssertEqual(viewModel.visibleCandidates.map(\.id), [2])
    }

    // MARK: - Watchlist button state

    func test_load_populatesWatchlistedMovieIDs_fromExistingWatchlistRows() async {
        let movie = Movie(tmdbID: 1, title: "Already saved", year: 2000)
        modelContext.insert(movie)
        modelContext.insert(Watchlist(userID: currentUser.id, movieID: 1))
        let service = PagedTrendingService(moviesByPage: [1: [movie]], totalPages: 1)
        let viewModel = makeViewModel(service: service)

        await viewModel.loadIfNeeded()

        XCTAssertTrue(viewModel.watchlistedMovieIDs.contains(1), "a card for an already-watchlisted movie must render filled on first appearance, not just after a tap")
    }

    func test_toggleWatchlist_addsMovieAndRecordsInteraction() async {
        let movie = Movie(tmdbID: 1, title: "One", year: 2000)
        let service = PagedTrendingService(moviesByPage: [1: [movie]], totalPages: 1)
        let viewModel = makeViewModel(service: service)
        await viewModel.loadIfNeeded()
        let candidate = viewModel.candidates[0]

        viewModel.toggleWatchlist(for: candidate)

        XCTAssertTrue(viewModel.watchlistedMovieIDs.contains(1))
        let watchlistRows = (try? modelContext.fetch(FetchDescriptor<Watchlist>())) ?? []
        XCTAssertEqual(watchlistRows.map(\.movieID), [1])
        let interactions = (try? modelContext.fetch(FetchDescriptor<DiscoverInteraction>())) ?? []
        XCTAssertEqual(interactions.map(\.action), [.watchlisted])
    }

    func test_toggleWatchlist_secondTap_removesFromWatchlistWithoutLoggingAnotherInteraction() async {
        let movie = Movie(tmdbID: 1, title: "One", year: 2000)
        let service = PagedTrendingService(moviesByPage: [1: [movie]], totalPages: 1)
        let viewModel = makeViewModel(service: service)
        await viewModel.loadIfNeeded()
        let candidate = viewModel.candidates[0]

        viewModel.toggleWatchlist(for: candidate) // add
        viewModel.toggleWatchlist(for: candidate) // remove

        XCTAssertFalse(viewModel.watchlistedMovieIDs.contains(1))
        let watchlistRows = (try? modelContext.fetch(FetchDescriptor<Watchlist>())) ?? []
        XCTAssertTrue(watchlistRows.isEmpty, "a second tap should remove the Watchlist row, not create a duplicate or leave it in place")
        let interactions = (try? modelContext.fetch(FetchDescriptor<DiscoverInteraction>())) ?? []
        XCTAssertEqual(interactions.count, 1, "removing shouldn't log a second interaction -- only the add is a discovery signal")
    }

    // MARK: - Rank it

    func test_markRanked_removesCandidateFromCurrentFeedAndLogsInteraction() async {
        let movieA = Movie(tmdbID: 1, title: "One", year: 2000)
        let movieB = Movie(tmdbID: 2, title: "Two", year: 2000)
        let service = PagedTrendingService(moviesByPage: [1: [movieA, movieB]], totalPages: 1)
        let viewModel = makeViewModel(service: service)
        await viewModel.loadIfNeeded()
        let rankedCandidate = viewModel.candidates[0]

        viewModel.markRanked(rankedCandidate)

        XCTAssertEqual(viewModel.candidates.map(\.id), [2], "a ranked movie should disappear from the feed immediately, not just on the next load")
        let interactions = (try? modelContext.fetch(FetchDescriptor<DiscoverInteraction>())) ?? []
        XCTAssertEqual(interactions.map { ($0.movieID, $0.action) }.map { $0.0 }, [1])
        XCTAssertEqual(interactions.map(\.action), [.logged])
    }

    func test_markRanked_clearsAnExistingWatchlistEntry() async {
        let movie = Movie(tmdbID: 1, title: "One", year: 2000)
        let service = PagedTrendingService(moviesByPage: [1: [movie]], totalPages: 1)
        let viewModel = makeViewModel(service: service)
        await viewModel.loadIfNeeded()
        let candidate = viewModel.candidates[0]
        viewModel.toggleWatchlist(for: candidate)
        XCTAssertTrue(viewModel.watchlistedMovieIDs.contains(1))

        viewModel.markRanked(candidate)

        XCTAssertFalse(viewModel.watchlistedMovieIDs.contains(1), "a ranked movie has a real score in the Library now -- it shouldn't still sit in 'want to watch'")
        let watchlistRows = (try? modelContext.fetch(FetchDescriptor<Watchlist>())) ?? []
        XCTAssertTrue(watchlistRows.isEmpty)
    }
}
