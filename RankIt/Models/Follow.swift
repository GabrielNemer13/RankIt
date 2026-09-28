import Foundation
import SwiftData

@Model
final class Follow {
    // No `.unique` -- CloudKit sync (planned) forbids it. Dedup is already
    // handled by FriendsView.toggleFollow checking for an existing row
    // before inserting, not by this constraint.
    var id: UUID = UUID()
    var followerID: UUID = UUID()
    var followeeID: UUID = UUID()

    init(
        id: UUID = UUID(),
        followerID: UUID,
        followeeID: UUID
    ) {
        self.id = id
        self.followerID = followerID
        self.followeeID = followeeID
    }
}
