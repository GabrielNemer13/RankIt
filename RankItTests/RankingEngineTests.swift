import XCTest
@testable import RankIt

/// Items are plain Ints standing in for movies, ordered best-to-worst
/// (index 0 = most preferred), matching RankingEngine's convention.
final class RankingEngineTests: XCTestCase {

    // MARK: - Empty tier

    func test_emptyTier_completesImmediatelyAtIndexZero() {
        let engine = RankingEngine<Int>(existingTier: [])

        XCTAssertTrue(engine.isComplete)
        XCTAssertNil(engine.currentComparisonIndex)
        XCTAssertNil(engine.currentComparisonItem)
        XCTAssertEqual(engine.insertionIndex, 0)
    }

    // MARK: - Odd-sized tier

    func test_oddSizedTier_locatesMiddleSlot() {
        // 5 items, best to worst.
        let engine = RankingEngine<Int>(existingTier: [10, 20, 30, 40, 50])

        // First comparison is against the midpoint of the full range [0, 5).
        XCTAssertEqual(engine.currentComparisonIndex, 2)
        XCTAssertEqual(engine.currentComparisonItem, 30)

        // New movie loses to 30 -> its slot is somewhere after index 2, range becomes [3, 5).
        XCTAssertNil(engine.recordComparison(winner: .existing))
        XCTAssertEqual(engine.currentComparisonIndex, 4) // mid of [3, 5)
        XCTAssertEqual(engine.currentComparisonItem, 50)

        // New movie beats 50 -> its slot is before index 4, range becomes [3, 4).
        XCTAssertNil(engine.recordComparison(winner: .new))
        XCTAssertEqual(engine.currentComparisonIndex, 3) // mid of [3, 4)
        XCTAssertEqual(engine.currentComparisonItem, 40)

        // New movie beats 40 too -> its slot is before index 3, i.e. exactly index 3.
        let result = engine.recordComparison(winner: .new)

        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(result, 3)
        XCTAssertEqual(engine.insertionIndex, 3)
    }

    // MARK: - Even-sized tier

    func test_evenSizedTier_locatesSlotBetweenExistingItems() {
        // 4 items, best to worst.
        let engine = RankingEngine<Int>(existingTier: [10, 20, 30, 40])

        // First comparison is against index (0+4)/2 = 2.
        XCTAssertEqual(engine.currentComparisonIndex, 2)
        XCTAssertEqual(engine.currentComparisonItem, 30)

        // New movie beats 30 -> slot is before index 2.
        XCTAssertNil(engine.recordComparison(winner: .new))
        XCTAssertEqual(engine.currentComparisonIndex, 1) // mid of [0, 2)
        XCTAssertEqual(engine.currentComparisonItem, 20)

        // New movie loses to 20 -> slot is after index 1, i.e. exactly index 2.
        let result = engine.recordComparison(winner: .existing)

        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(result, 2)
    }

    // MARK: - Insertion at both ends

    func test_newMovieBeatsEveryComparison_insertsAtTop() {
        let engine = RankingEngine<Int>(existingTier: [10, 20, 30, 40, 50])

        while !engine.isComplete {
            engine.recordComparison(winner: .new)
        }

        XCTAssertEqual(engine.insertionIndex, 0)
    }

    func test_newMovieLosesEveryComparison_insertsAtBottom() {
        let engine = RankingEngine<Int>(existingTier: [10, 20, 30, 40, 50])

        while !engine.isComplete {
            engine.recordComparison(winner: .existing)
        }

        XCTAssertEqual(engine.insertionIndex, 5)
    }

    func test_singleItemTier_newMovieWins_insertsBeforeIt() {
        let engine = RankingEngine<Int>(existingTier: [42])

        XCTAssertEqual(engine.currentComparisonItem, 42)
        let result = engine.recordComparison(winner: .new)

        XCTAssertEqual(result, 0)
        XCTAssertTrue(engine.isComplete)
    }

    func test_singleItemTier_newMovieLoses_insertsAfterIt() {
        let engine = RankingEngine<Int>(existingTier: [42])

        let result = engine.recordComparison(winner: .existing)

        XCTAssertEqual(result, 1)
        XCTAssertTrue(engine.isComplete)
    }

    // MARK: - Undo

    func test_undoLastComparison_revertsSearchRangeAndAllowsReanswering() {
        let engine = RankingEngine<Int>(existingTier: [10, 20, 30, 40, 50])

        engine.recordComparison(winner: .existing) // misclick
        XCTAssertEqual(engine.currentComparisonIndex, 4) // mid of [3, 5)

        XCTAssertTrue(engine.undoLastComparison())
        XCTAssertEqual(engine.currentComparisonIndex, 2) // back to the original mid of [0, 5)
        XCTAssertFalse(engine.isComplete)

        // Re-answer the other way and confirm it produces the expected,
        // different outcome rather than replaying stale state.
        engine.recordComparison(winner: .new)
        XCTAssertEqual(engine.currentComparisonIndex, 1)
    }

    func test_undoWithNoHistory_returnsFalseAndLeavesStateUnchanged() {
        let engine = RankingEngine<Int>(existingTier: [10, 20, 30])

        XCTAssertFalse(engine.undoLastComparison())
        XCTAssertEqual(engine.currentComparisonIndex, 1)
    }

    // MARK: - Ties

    func test_tieOnFirstComparison_stopsImmediatelyWithoutNarrowing() {
        let engine = RankingEngine<Int>(existingTier: [10, 20, 30, 40, 50])

        XCTAssertEqual(engine.currentComparisonIndex, 2)
        let result = engine.recordComparison(winner: .tie)

        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(engine.completion, .tie(withIndex: 2))
        // A tied completion is not a resolved insertion index.
        XCTAssertNil(result)
        XCTAssertNil(engine.insertionIndex)
        // The search stops here — no further comparison is offered.
        XCTAssertNil(engine.currentComparisonIndex)
        XCTAssertNil(engine.currentComparisonItem)
    }

    func test_tieAfterPartialNarrowing_stopsAtCurrentIndexNotOriginalMidpoint() {
        let engine = RankingEngine<Int>(existingTier: [10, 20, 30, 40, 50])

        // Narrow once: new movie loses to 30 -> range becomes [3, 5).
        XCTAssertNil(engine.recordComparison(winner: .existing))
        XCTAssertEqual(engine.currentComparisonIndex, 4) // mid of [3, 5)

        // Tie with 50 rather than resolving further.
        let result = engine.recordComparison(winner: .tie)

        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(engine.completion, .tie(withIndex: 4))
        XCTAssertNil(result)
        XCTAssertNil(engine.insertionIndex)
    }

    func test_tieInSingleItemTier() {
        let engine = RankingEngine<Int>(existingTier: [42])

        XCTAssertEqual(engine.currentComparisonItem, 42)
        engine.recordComparison(winner: .tie)

        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(engine.completion, .tie(withIndex: 0))
        XCTAssertNil(engine.insertionIndex)
    }

    // MARK: - Comparisons never cross tiers

    func test_engineOnlyEverIndexesWithinSuppliedTier() {
        let tier = [10, 20, 30, 40, 50, 60, 70]
        let engine = RankingEngine<Int>(existingTier: tier)

        while !engine.isComplete {
            let index = engine.currentComparisonIndex!
            XCTAssertTrue(tier.indices.contains(index))
            engine.recordComparison(winner: index.isMultiple(of: 2) ? .new : .existing)
        }

        XCTAssertNotNil(engine.insertionIndex)
    }
}
