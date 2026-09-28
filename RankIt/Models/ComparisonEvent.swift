import Foundation
import SwiftData

/// Records a single "A vs B" head-to-head answer, for the comparison
/// history view and undo. `movieAID` is always the movie being logged or
/// re-ranked; `movieBID` is the existing tier movie it was compared
/// against. `tier` and the optional `winnerID` (nil means a tie -- neither
/// movie "won") were added specifically so this model could reconstruct a
/// movie's comparison history; the original schema had a non-optional
/// `winnerID` with no way to represent a tie.
@Model
final class ComparisonEvent {
    // No `.unique` -- CloudKit sync (planned) forbids it.
    var id: UUID = UUID()
    var userID: UUID = UUID()
    var movieAID: Int = 0
    var movieBID: Int = 0
    var winnerID: Int?
    var tier: MovieTier = MovieTier.loved
    var timestamp: Date = Date.now

    init(
        id: UUID = UUID(),
        userID: UUID,
        movieAID: Int,
        movieBID: Int,
        winnerID: Int?,
        tier: MovieTier,
        timestamp: Date = .now
    ) {
        self.id = id
        self.userID = userID
        self.movieAID = movieAID
        self.movieBID = movieBID
        self.winnerID = winnerID
        self.tier = tier
        self.timestamp = timestamp
    }
}
