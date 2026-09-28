import Foundation
import SwiftData

/// There's no auth/account screen yet, so the app operates as a single
/// local user. This fetches that user (creating one on first launch) so
/// `LoggedMovie.userID` etc. have something real to point at.
enum CurrentUserProvider {
    @discardableResult
    static func fetchOrCreateCurrentUser(in context: ModelContext) -> User {
        if let existing = try? context.fetch(FetchDescriptor<User>()).first {
            return existing
        }
        let user = User(username: "me", displayName: "Me")
        context.insert(user)
        return user
    }

    /// Whether a `User` row already exists -- call this *before*
    /// `fetchOrCreateCurrentUser`, which would otherwise create one and
    /// make this always return true. Used to detect an existing install
    /// (from before onboarding existed) so it isn't forced through
    /// first-run onboarding retroactively -- see `OnboardingGate`.
    static func hasExistingUser(in context: ModelContext) -> Bool {
        !((try? context.fetch(FetchDescriptor<User>())) ?? []).isEmpty
    }
}
