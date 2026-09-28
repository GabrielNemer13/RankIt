import XCTest
@testable import RankIt

final class LoggedMovieDisplayOrderTests: XCTestCase {

    func test_tiedItems_sortByRankPositionThenNewestWatchedDateFirst() {
        let userID = UUID()
        let now = Date()

        // Two movies tied at rankPosition 2 -- the more recently watched
        // one should display first. A third movie at rankPosition 0 (a
        // different, non-tied slot) should always sort ahead of both.
        let olderTie = LoggedMovie(
            userID: userID, movieID: 1, watchedDate: now.addingTimeInterval(-86_400),
            tier: .loved, rankPosition: 2
        )
        let newerTie = LoggedMovie(
            userID: userID, movieID: 2, watchedDate: now,
            tier: .loved, rankPosition: 2
        )
        let topOfTier = LoggedMovie(
            userID: userID, movieID: 3, watchedDate: now.addingTimeInterval(-999_999),
            tier: .loved, rankPosition: 0
        )

        let sorted = [olderTie, newerTie, topOfTier].sorted(by: LoggedMovie.isOrderedForDisplay)

        XCTAssertEqual(sorted.map(\.movieID), [3, 2, 1])
    }

    func test_untiedItems_sortByRankPositionAlone() {
        let userID = UUID()
        let now = Date()

        let third = LoggedMovie(userID: userID, movieID: 30, watchedDate: now, tier: .liked, rankPosition: 2)
        let first = LoggedMovie(userID: userID, movieID: 10, watchedDate: now.addingTimeInterval(-10), tier: .liked, rankPosition: 0)
        let second = LoggedMovie(userID: userID, movieID: 20, watchedDate: now.addingTimeInterval(-20), tier: .liked, rankPosition: 1)

        let sorted = [third, first, second].sorted(by: LoggedMovie.isOrderedForDisplay)

        XCTAssertEqual(sorted.map(\.movieID), [10, 20, 30])
    }
}
