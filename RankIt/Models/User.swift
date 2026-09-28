import Foundation
import SwiftData

@Model
final class User {
    // No `.unique` constraint -- CloudKit sync (planned) forbids it; every
    // stored property below also gets an inline default for the same
    // reason (see Movie.voteAverage for the earlier lightweight-migration
    // incident this pattern avoids). Duplicate-prevention here is handled
    // by CurrentUserProvider's fetch-first logic, not a schema constraint.
    var id: UUID = UUID()
    var username: String = ""
    var displayName: String = ""
    var avatarURL: URL?
    var bio: String?
    var joinedDate: Date = Date.now

    init(
        id: UUID = UUID(),
        username: String,
        displayName: String,
        avatarURL: URL? = nil,
        bio: String? = nil,
        joinedDate: Date = .now
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.bio = bio
        self.joinedDate = joinedDate
    }
}
