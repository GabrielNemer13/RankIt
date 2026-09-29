import XCTest
import SwiftData
@testable import RankIt

final class LibraryExporterTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var userID: UUID!

    override func setUpWithError() throws {
        let schema = Schema([
            User.self, Movie.self, LoggedMovie.self, ComparisonEvent.self,
            Watchlist.self, Follow.self, ActivityFeedItem.self, Trailer.self,
            DiscoverInteraction.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(modelContainer)
        userID = UUID()
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
        userID = nil
    }

    func test_build_includesLoggedMoviesWithCorrectRankAndScore() {
        let movieA = Movie(tmdbID: 1, title: "Best", year: 2000)
        let movieB = Movie(tmdbID: 2, title: "Worst", year: 2001)
        modelContext.insert(movieA)
        modelContext.insert(movieB)
        modelContext.insert(LoggedMovie(userID: userID, movieID: 1, tier: .loved, rankPosition: 0))
        modelContext.insert(LoggedMovie(userID: userID, movieID: 2, tier: .loved, rankPosition: 1))

        let export = LibraryExporter.build(userID: userID, modelContext: modelContext)

        XCTAssertEqual(export.formatVersion, LibraryExport.currentFormatVersion)
        XCTAssertEqual(export.loggedMovies.count, 2)
        let best = export.loggedMovies.first { $0.tmdbID == 1 }
        let worst = export.loggedMovies.first { $0.tmdbID == 2 }
        XCTAssertEqual(best?.title, "Best")
        XCTAssertEqual(best?.displayRank, 1)
        XCTAssertEqual(best?.score, 10.0)
        XCTAssertEqual(worst?.displayRank, 2)
        XCTAssertEqual(worst?.score, 7.0)
    }

    func test_build_ordersLoggedMoviesByTierThenRank() {
        modelContext.insert(Movie(tmdbID: 1, title: "Disliked", year: 2000))
        modelContext.insert(Movie(tmdbID: 2, title: "Loved", year: 2000))
        modelContext.insert(LoggedMovie(userID: userID, movieID: 1, tier: .disliked, rankPosition: 0))
        modelContext.insert(LoggedMovie(userID: userID, movieID: 2, tier: .loved, rankPosition: 0))

        let export = LibraryExporter.build(userID: userID, modelContext: modelContext)

        XCTAssertEqual(export.loggedMovies.map(\.tier), ["loved", "disliked"], "tiers should be exported loved-first, matching Library's own display order")
    }

    func test_build_includesWatchlistMostRecentFirst() {
        let movie = Movie(tmdbID: 1, title: "Saved", year: 2000)
        modelContext.insert(movie)
        modelContext.insert(Watchlist(userID: userID, movieID: 1, addedDate: Date(timeIntervalSince1970: 100)))

        let export = LibraryExporter.build(userID: userID, modelContext: modelContext)

        XCTAssertEqual(export.watchlist.count, 1)
        XCTAssertEqual(export.watchlist.first?.title, "Saved")
        XCTAssertEqual(export.watchlist.first?.tmdbID, 1)
    }

    func test_build_missingCachedMovie_fallsBackToUnknownTitleRatherThanDroppingTheRow() {
        modelContext.insert(LoggedMovie(userID: userID, movieID: 999, tier: .liked, rankPosition: 0))

        let export = LibraryExporter.build(userID: userID, modelContext: modelContext)

        XCTAssertEqual(export.loggedMovies.count, 1)
        XCTAssertEqual(export.loggedMovies.first?.title, "Unknown movie")
    }

    func test_build_onlyIncludesTheGivenUsersRows() {
        let otherUserID = UUID()
        modelContext.insert(Movie(tmdbID: 1, title: "Mine", year: 2000))
        modelContext.insert(Movie(tmdbID: 2, title: "Theirs", year: 2000))
        modelContext.insert(LoggedMovie(userID: userID, movieID: 1, tier: .loved, rankPosition: 0))
        modelContext.insert(LoggedMovie(userID: otherUserID, movieID: 2, tier: .loved, rankPosition: 0))

        let export = LibraryExporter.build(userID: userID, modelContext: modelContext)

        XCTAssertEqual(export.loggedMovies.map(\.tmdbID), [1])
    }

    func test_exportToTemporaryFile_writesValidDecodableJSON() {
        modelContext.insert(Movie(tmdbID: 1, title: "Roundtrip", year: 2000))
        modelContext.insert(LoggedMovie(userID: userID, movieID: 1, tier: .liked, rankPosition: 0))

        guard let url = LibraryExporter.exportToTemporaryFile(userID: userID, modelContext: modelContext) else {
            return XCTFail("expected a file URL")
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try? Data(contentsOf: url)
        XCTAssertNotNil(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode(LibraryExport.self, from: data ?? Data())
        XCTAssertEqual(decoded?.loggedMovies.first?.title, "Roundtrip")
        XCTAssertEqual(decoded?.formatVersion, 1)
    }
}
