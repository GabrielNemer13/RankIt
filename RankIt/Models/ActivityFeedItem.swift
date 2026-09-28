import Foundation
import SwiftData

enum ActivityType: String, Codable, CaseIterable {
    case logged
    case watchlisted
    case reviewed
    case followed
}

/// Denormalized for feed performance. `refID` points at the object the
/// activity concerns (a LoggedMovie.id for `.logged`, a Watchlist.id for
/// `.watchlisted`, or a Follow.id for `.followed`).
@Model
final class ActivityFeedItem {
    // No `.unique` -- CloudKit sync (planned) forbids it. Each activity is
    // its own event; there's no dedup concern (never fetched/compared by
    // id before insert, same as the other event-log models).
    var id: UUID = UUID()
    var userID: UUID = UUID()
    var type: ActivityType = ActivityType.logged
    var refID: UUID = UUID()
    var timestamp: Date = Date.now

    init(
        id: UUID = UUID(),
        userID: UUID,
        type: ActivityType,
        refID: UUID,
        timestamp: Date = .now
    ) {
        self.id = id
        self.userID = userID
        self.type = type
        self.refID = refID
        self.timestamp = timestamp
    }
}
