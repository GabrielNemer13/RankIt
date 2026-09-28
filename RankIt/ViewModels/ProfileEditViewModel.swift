import Foundation
import SwiftData
import Observation

/// Backs both onboarding's "Create your profile" step and the Friends
/// tab's edit-profile sheet, so the two share identical validation and
/// save behavior. `save()` mutates the given `User` in place -- it never
/// inserts a new row, so profile creation during onboarding updates the
/// placeholder `User` that `CurrentUserProvider` already created rather
/// than duplicating it.
@MainActor
@Observable
final class ProfileEditViewModel {
    var displayName: String
    var username: String
    private(set) var didSave = false

    private let user: User
    private let modelContext: ModelContext

    init(user: User, modelContext: ModelContext) {
        self.user = user
        self.modelContext = modelContext
        self.displayName = user.displayName
        self.username = user.username
    }

    var displayNameError: String? {
        if case .failure(let error) = ProfileValidator.validateDisplayName(displayName) {
            return error.errorDescription
        }
        return nil
    }

    var usernameError: String? {
        if case .failure(let error) = ProfileValidator.validateUsername(username, existingUsernames: otherUsernames()) {
            return error.errorDescription
        }
        return nil
    }

    var isValid: Bool {
        displayNameError == nil && usernameError == nil
    }

    /// Validates, and if valid, writes the trimmed/normalized values onto
    /// the existing `User` and saves. Returns whether it saved.
    @discardableResult
    func save() -> Bool {
        guard case .success(let validDisplayName) = ProfileValidator.validateDisplayName(displayName),
              case .success(let validUsername) = ProfileValidator.validateUsername(username, existingUsernames: otherUsernames())
        else { return false }

        user.displayName = validDisplayName
        user.username = validUsername
        try? modelContext.save()
        didSave = true
        return true
    }

    private func otherUsernames() -> Set<String> {
        let userID = user.id
        let descriptor = FetchDescriptor<User>()
        let allUsers = (try? modelContext.fetch(descriptor)) ?? []
        return Set(allUsers.filter { $0.id != userID }.map { $0.username.lowercased() })
    }
}
