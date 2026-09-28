import Foundation

/// Drives the tiered binary insertion ranking described in SPEC.md.
///
/// A `RankingEngine` operates on a single tier's worth of already-ranked
/// items — tier selection happens before an engine is created, and the
/// engine never compares across tiers. Items are ordered best-to-worst, so
/// index `0` is the top of the tier and the insertion index this engine
/// produces follows the same convention: after inserting the new item at
/// `insertionIndex`, that index holds the new item.
///
/// Usage: construct with the tier's current items, read
/// `currentComparisonItem` to know what to show the user, call
/// `recordComparison(winner:)` with their answer, and repeat until
/// `isComplete` is true. Check `completion` to find out whether the result
/// is a normal insertion or a tie. `undoLastComparison()` rewinds exactly
/// one step for misclicks.
final class RankingEngine<Item> {
    enum Winner {
        /// The new movie being inserted beat the item at `currentComparisonIndex`.
        case new
        /// The existing item at `currentComparisonIndex` beat the new movie.
        case existing
        /// The user couldn't call it — the new movie ties with the item at
        /// `currentComparisonIndex`. This stops the search immediately;
        /// unlike `.new`/`.existing` it does not narrow the range further.
        case tie
    }

    /// The final outcome of a completed engine: either a normal insertion
    /// slot, or a tie with an existing item at a given index. Callers use
    /// this (rather than `insertionIndex` alone) to know whether to shift
    /// every item below the slot down by one, or to reuse the tied item's
    /// `rankPosition` unchanged.
    enum Completion: Equatable {
        case insert(at: Int)
        case tie(withIndex: Int)
    }

    private struct HistoryEntry {
        let lowerBound: Int
        let upperBound: Int
        let tieIndexBefore: Int?
    }

    private(set) var items: [Item]
    private(set) var lowerBound: Int
    private(set) var upperBound: Int
    private(set) var tieIndex: Int?
    private var history: [HistoryEntry] = []

    /// - Parameter existingTier: the tier's items, already ordered best-to-worst
    ///   (index 0 = most preferred). Must not contain the item being inserted.
    init(existingTier items: [Item]) {
        self.items = items
        self.lowerBound = 0
        self.upperBound = items.count
        self.tieIndex = nil
    }

    /// True once a result has been found and no more comparisons are needed —
    /// either the search range has collapsed, or the user called a tie.
    var isComplete: Bool {
        tieIndex != nil || lowerBound >= upperBound
    }

    /// Index of the item to compare the new movie against next, or `nil` if complete.
    var currentComparisonIndex: Int? {
        isComplete ? nil : (lowerBound + upperBound) / 2
    }

    /// The item to compare the new movie against next, or `nil` if complete.
    var currentComparisonItem: Item? {
        currentComparisonIndex.map { items[$0] }
    }

    /// Whether `undoLastComparison()` currently has anything to revert.
    var canUndo: Bool {
        !history.isEmpty
    }

    /// The final outcome, or `nil` while comparisons are still needed.
    var completion: Completion? {
        if let tieIndex { return .tie(withIndex: tieIndex) }
        guard isComplete else { return nil }
        return .insert(at: lowerBound)
    }

    /// The index the new movie should be inserted at, or `nil` if more
    /// comparisons remain OR the result was a tie (see `completion`).
    var insertionIndex: Int? {
        guard tieIndex == nil, isComplete else { return nil }
        return lowerBound
    }

    /// Records the answer to the current comparison. For `.new`/`.existing`
    /// this narrows the search range as before. For `.tie` the search stops
    /// immediately at the current comparison index rather than narrowing.
    ///
    /// Returns `insertionIndex` (i.e. non-nil only for a normal, non-tied
    /// completion) if this was the final comparison, `nil` otherwise. Use
    /// `completion` to also observe a tie result.
    ///
    /// No-op (returns `insertionIndex`) if called after the engine is already complete.
    @discardableResult
    func recordComparison(winner: Winner) -> Int? {
        guard let mid = currentComparisonIndex else { return insertionIndex }
        history.append(HistoryEntry(lowerBound: lowerBound, upperBound: upperBound, tieIndexBefore: tieIndex))
        switch winner {
        case .new:
            // New movie is better than mid — its slot is somewhere before mid.
            upperBound = mid
        case .existing:
            // New movie is worse than mid — its slot is somewhere after mid.
            lowerBound = mid + 1
        case .tie:
            // Too close to call — stop here and tie with mid rather than narrowing further.
            tieIndex = mid
        }
        return insertionIndex
    }

    /// Reverts the most recent `recordComparison(winner:)` call, restoring the
    /// search range (and tie state) to what it was beforehand. Returns
    /// `false` if there was nothing to undo.
    @discardableResult
    func undoLastComparison() -> Bool {
        guard let entry = history.popLast() else { return false }
        lowerBound = entry.lowerBound
        upperBound = entry.upperBound
        tieIndex = entry.tieIndexBefore
        return true
    }
}
