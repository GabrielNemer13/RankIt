import XCTest
@testable import RankIt

final class RatingScoreTests: XCTestCase {

    // MARK: - Band edges

    func test_topRankOfMultiItemTier_scoresAtBandHigh() {
        XCTAssertEqual(RatingScore.score(tier: .loved, rank: 1, tierCount: 5), 10.0)
        XCTAssertEqual(RatingScore.score(tier: .liked, rank: 1, tierCount: 5), 6.9)
        XCTAssertEqual(RatingScore.score(tier: .disliked, rank: 1, tierCount: 5), 3.9)
    }

    func test_bottomRankOfMultiItemTier_scoresAtBandLow() {
        XCTAssertEqual(RatingScore.score(tier: .loved, rank: 5, tierCount: 5), 7.0)
        XCTAssertEqual(RatingScore.score(tier: .liked, rank: 5, tierCount: 5), 4.0)
        XCTAssertEqual(RatingScore.score(tier: .disliked, rank: 5, tierCount: 5), 0.0)
    }

    func test_middleRank_isSpreadEvenlyAcrossBand() {
        // 3-item Loved tier: rank 1 -> 10.0, rank 3 -> 7.0, rank 2 -> midpoint 8.5.
        XCTAssertEqual(RatingScore.score(tier: .loved, rank: 2, tierCount: 3), 8.5)
    }

    // MARK: - Single-item tier

    func test_singleItemTier_scoresAtTopOfBand() {
        XCTAssertEqual(RatingScore.score(tier: .loved, rank: 1, tierCount: 1), 10.0)
        XCTAssertEqual(RatingScore.score(tier: .liked, rank: 1, tierCount: 1), 6.9)
        XCTAssertEqual(RatingScore.score(tier: .disliked, rank: 1, tierCount: 1), 3.9)
    }

    // MARK: - Monotonicity

    func test_rankOrdering_isMonotonicWithinATier() {
        let tierCount = 11
        let scores = (1...tierCount).map { RatingScore.score(tier: .loved, rank: $0, tierCount: tierCount) }
        for (a, b) in zip(scores, scores.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a, b, "score must never increase as rank gets worse")
        }
    }

    func test_rankOrdering_isMonotonicAcrossAllThreeTiers_evenAfterRounding() {
        // A stress tier size chosen to be large relative to each band's
        // range, so rounding to one decimal is likely to produce ties --
        // exactly the case that must still stay non-increasing.
        let tierCount = 37
        for tier in MovieTier.allCases {
            let scores = (1...tierCount).map { RatingScore.score(tier: tier, rank: $0, tierCount: tierCount) }
            for (a, b) in zip(scores, scores.dropFirst()) {
                XCTAssertGreaterThanOrEqual(a, b, "\(tier) rank ordering must stay monotonic after rounding")
            }
        }
    }

    // MARK: - No cross-tier overlap

    func test_lowestScoreInATier_neverExceedsNextTiersHighestScore() {
        let lovedLowest = RatingScore.score(tier: .loved, rank: 50, tierCount: 50)
        let likedHighest = RatingScore.score(tier: .liked, rank: 1, tierCount: 50)
        XCTAssertGreaterThan(lovedLowest, likedHighest)

        let likedLowest = RatingScore.score(tier: .liked, rank: 50, tierCount: 50)
        let dislikedHighest = RatingScore.score(tier: .disliked, rank: 1, tierCount: 50)
        XCTAssertGreaterThan(likedLowest, dislikedHighest)
    }

    // MARK: - Ties (via scores(forDisplayOrderedTier:))

    private func loggedMovie(userID: UUID, movieID: Int, tier: MovieTier, rankPosition: Int, watchedDate: Date) -> LoggedMovie {
        LoggedMovie(userID: userID, movieID: movieID, watchedDate: watchedDate, tier: tier, rankPosition: rankPosition)
    }

    func test_scoresForDisplayOrderedTier_tiedEntries_getIdenticalScores() {
        let userID = UUID()
        // Two entries tied at rankPosition 0, then one at rankPosition 2 --
        // display-sorted per LoggedMovie.isOrderedForDisplay (rankPosition
        // ascending, watchedDate descending as the tie-break).
        let tiedNewer = loggedMovie(userID: userID, movieID: 1, tier: .loved, rankPosition: 0, watchedDate: Date(timeIntervalSince1970: 200))
        let tiedOlder = loggedMovie(userID: userID, movieID: 2, tier: .loved, rankPosition: 0, watchedDate: Date(timeIntervalSince1970: 100))
        let third = loggedMovie(userID: userID, movieID: 3, tier: .loved, rankPosition: 2, watchedDate: Date(timeIntervalSince1970: 50))
        let entries = [tiedNewer, tiedOlder, third] // already in display order

        let scores = RatingScore.scores(forDisplayOrderedTier: entries)

        XCTAssertEqual(scores[tiedNewer.id], scores[tiedOlder.id], "tied entries must score identically regardless of the watchedDate tiebreak")
        XCTAssertEqual(scores[tiedNewer.id], 10.0, "the tied pair occupies the tier's #1 slot")
        XCTAssertEqual(scores[third.id], 7.0, "the second distinct slot (of 2) is the bottom of the band")
    }

    func test_scoresForDisplayOrderedTier_noTies_matchesDirectRankCalculation() {
        let userID = UUID()
        let entries = (0..<4).map { i in
            loggedMovie(userID: userID, movieID: i, tier: .liked, rankPosition: i, watchedDate: .now)
        }

        let scores = RatingScore.scores(forDisplayOrderedTier: entries)

        for (index, entry) in entries.enumerated() {
            let expected = RatingScore.score(tier: .liked, rank: index + 1, tierCount: entries.count)
            XCTAssertEqual(scores[entry.id], expected)
        }
    }

    func test_scoresForDisplayOrderedTier_emptyTier_returnsEmptyMap() {
        XCTAssertTrue(RatingScore.scores(forDisplayOrderedTier: []).isEmpty)
    }

    func test_scoresForDisplayOrderedTier_singleEntry_scoresAtTopOfBand() {
        let entry = loggedMovie(userID: UUID(), movieID: 1, tier: .disliked, rankPosition: 0, watchedDate: .now)

        let scores = RatingScore.scores(forDisplayOrderedTier: [entry])

        XCTAssertEqual(scores[entry.id], 3.9)
    }
}
