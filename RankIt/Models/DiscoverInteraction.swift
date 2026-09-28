import Foundation
import SwiftData

enum DiscoverAction: String, Codable, CaseIterable {
    case watchlisted
    case skipped
    case logged
}

/// Used to avoid resurfacing skipped movies in Discover; skipping the same
/// movie twice should deprioritize it heavily.
@Model
final class DiscoverInteraction {
    // No `.unique` -- CloudKit sync (planned) forbids it. Not a dedup
    // mechanism here anyway: repeated interactions with the same movie are
    // valid and expected (e.g. skipping twice is meaningful history).
    var id: UUID = UUID()
    var userID: UUID = UUID()
    var movieID: Int = 0
    var action: DiscoverAction = DiscoverAction.watchlisted
    var timestamp: Date = Date.now

    init(
        id: UUID = UUID(),
        userID: UUID,
        movieID: Int,
        action: DiscoverAction,
        timestamp: Date = .now
    ) {
        self.id = id
        self.userID = userID
        self.movieID = movieID
        self.action = action
        self.timestamp = timestamp
    }
}
