import XCTest
@testable import RankIt

@MainActor
final class DetailActionsTests: XCTestCase {

    func test_readOnly_exposesNoDestructiveOrEditActions() {
        let actions = DetailActions.available(for: .readOnly)

        XCTAssertNil(actions.removeButtonTitle)
        XCTAssertFalse(actions.canRemove)
        XCTAssertFalse(actions.canChangeTier)
        XCTAssertFalse(actions.canReRank)
        XCTAssertFalse(actions.canViewComparisonHistory)
    }

    func test_library_exposesRemoveChangeTierReRankAndComparisonHistory() {
        let logged = LoggedMovie(userID: UUID(), movieID: 1, tier: .loved, rankPosition: 0)
        let actions = DetailActions.available(for: .library(loggedMovie: logged))

        XCTAssertEqual(actions.removeButtonTitle, "Remove from Library")
        XCTAssertTrue(actions.canRemove)
        XCTAssertTrue(actions.canChangeTier)
        XCTAssertTrue(actions.canReRank)
        XCTAssertTrue(actions.canViewComparisonHistory)
    }

    func test_watchlist_exposesOnlyRemove() {
        let entry = Watchlist(userID: UUID(), movieID: 1)
        let actions = DetailActions.available(for: .watchlist(entry: entry))

        XCTAssertEqual(actions.removeButtonTitle, "Remove from Watchlist")
        XCTAssertTrue(actions.canRemove)
        XCTAssertFalse(actions.canChangeTier)
        XCTAssertFalse(actions.canReRank)
        XCTAssertFalse(actions.canViewComparisonHistory)
    }
}

@MainActor
final class MovieDetailContextTests: XCTestCase {

    /// This is the seam `LibraryView` calls for every row -- confirms the
    /// Friends flow (which passes `isOwnLibrary: false` for a followed
    /// user's library) always resolves to `.readOnly`, regardless of the
    /// row's own `LoggedMovie`.
    func test_forLibraryRow_isReadOnlyForFollowedUsersLibrary() {
        let logged = LoggedMovie(userID: UUID(), movieID: 1, tier: .loved, rankPosition: 0)

        XCTAssertEqual(MovieDetailContext.forLibraryRow(loggedMovie: logged, isOwnLibrary: false), .readOnly)
    }

    func test_forLibraryRow_isLibraryForOwnLibrary() {
        let logged = LoggedMovie(userID: UUID(), movieID: 1, tier: .loved, rankPosition: 0)

        XCTAssertEqual(MovieDetailContext.forLibraryRow(loggedMovie: logged, isOwnLibrary: true), .library(loggedMovie: logged))
    }

    func test_loggedMovie_accessorReturnsValueOnlyForLibraryCase() {
        let logged = LoggedMovie(userID: UUID(), movieID: 1, tier: .loved, rankPosition: 0)
        let entry = Watchlist(userID: UUID(), movieID: 1)

        XCTAssertEqual(MovieDetailContext.library(loggedMovie: logged).loggedMovie, logged)
        XCTAssertNil(MovieDetailContext.watchlist(entry: entry).loggedMovie)
        XCTAssertNil(MovieDetailContext.readOnly.loggedMovie)
    }
}
