import Foundation
import SwiftData

@Model
final class Watchlist {
    // No `.unique` -- CloudKit sync (planned) forbids it. Dedup is already
    // handled by DiscoverViewModel's isAlreadyOnWatchlist(movieID:) check
    // before insert, not by this constraint.
    var id: UUID = UUID()
    var userID: UUID = UUID()
    var movieID: Int = 0
    var addedDate: Date = Date.now

    init(
        id: UUID = UUID(),
        userID: UUID,
        movieID: Int,
        addedDate: Date = .now
    ) {
        self.id = id
        self.userID = userID
        self.movieID = movieID
        self.addedDate = addedDate
    }
}
