import Foundation

/// A Beli-style 0.0–10.0 "my rating" derived purely from a movie's tier and
/// its position within that tier — never stored (see the type doc below),
/// so it's always in sync with the current ranking.
enum RatingScore {
    struct Band {
        let low: Double
        let high: Double
    }

    /// Non-overlapping by design (each tier's `low` is strictly greater
    /// than the tier below's `high`), so a tier's lowest possible score
    /// can never cross into the next tier's range. Edit these three lines
    /// to change the bands.
    static let bands: [MovieTier: Band] = [
        .loved: Band(low: 7.0, high: 10.0),
        .liked: Band(low: 4.0, high: 6.9),
        .disliked: Band(low: 0.0, high: 3.9)
    ]

    /// `rank` and `tierCount` are in terms of *distinct rank slots*, not
    /// raw item count -- movies tied against each other (sharing a
    /// `rankPosition`) occupy the same slot, so pass the same `rank` for
    /// each to get identical scores. `rank` is 1-based, with `1` being the
    /// best (top of the tier's band) and `tierCount` the worst (bottom).
    ///
    /// A single-slot tier (`tierCount == 1`) always scores at the top of
    /// its band -- there's no "worst" to spread down toward.
    static func score(tier: MovieTier, rank: Int, tierCount: Int) -> Double {
        guard let band = bands[tier], tierCount > 0 else { return 0 }
        guard tierCount > 1 else { return band.high }

        let clampedRank = max(1, min(rank, tierCount))
        let fraction = Double(clampedRank - 1) / Double(tierCount - 1)
        let raw = band.high - fraction * (band.high - band.low)
        // One decimal place, matching the display format.
        return (raw * 10).rounded() / 10
    }

    /// Convenience for a whole tier's `LoggedMovie`s, already sorted for
    /// display (`LoggedMovie.isOrderedForDisplay` / `.queryOrder`): groups
    /// entries that share a `rankPosition` (ties) into one slot, then
    /// scores each entry by its slot's ordinal position among the tier's
    /// distinct slots. Returns a score per entry `id`.
    static func scores(forDisplayOrderedTier entries: [LoggedMovie]) -> [UUID: Double] {
        guard let tier = entries.first?.tier else { return [:] }
        let distinctSlotCount = Set(entries.map(\.rankPosition)).count

        var result: [UUID: Double] = [:]
        var lastRankPosition: Int?
        var slotIndex = 0
        for entry in entries {
            if lastRankPosition != entry.rankPosition {
                slotIndex += 1
                lastRankPosition = entry.rankPosition
            }
            result[entry.id] = score(tier: tier, rank: slotIndex, tierCount: distinctSlotCount)
        }
        return result
    }
}
