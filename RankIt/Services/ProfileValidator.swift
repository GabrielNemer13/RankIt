import Foundation

enum ProfileValidationError: LocalizedError, Equatable {
    case displayNameEmpty
    case displayNameTooLong(limit: Int)
    case usernameEmpty
    case usernameInvalidCharacters
    case usernameTooLong(limit: Int)
    case usernameTaken

    var errorDescription: String? {
        switch self {
        case .displayNameEmpty:
            return "Display name can't be empty."
        case .displayNameTooLong(let limit):
            return "Display name must be \(limit) characters or fewer."
        case .usernameEmpty:
            return "Username can't be empty."
        case .usernameInvalidCharacters:
            return "Username can only contain lowercase letters, numbers, and underscores."
        case .usernameTooLong(let limit):
            return "Username must be \(limit) characters or fewer."
        case .usernameTaken:
            return "That username is already taken."
        }
    }
}

/// Shared by onboarding's "Create your profile" step and the Friends tab's
/// edit-profile sheet, so both enforce identical rules.
enum ProfileValidator {
    static let displayNameMaxLength = 50
    static let usernameMaxLength = 20
    private static let usernamePattern = "^[a-z0-9_]+$"

    static func validateDisplayName(_ raw: String) -> Result<String, ProfileValidationError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.displayNameEmpty) }
        guard trimmed.count <= displayNameMaxLength else {
            return .failure(.displayNameTooLong(limit: displayNameMaxLength))
        }
        return .success(trimmed)
    }

    /// - Parameter existingUsernames: other users' lowercased usernames to
    ///   check against (exclude the profile being edited). Only checked
    ///   against local `User` rows for now.
    ///   TODO: once there's a backend, replace/augment this with a
    ///   server-side uniqueness check against the full public directory --
    ///   two devices could otherwise pick the same username locally.
    static func validateUsername(_ raw: String, existingUsernames: Set<String>) -> Result<String, ProfileValidationError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.usernameEmpty) }
        guard trimmed.count <= usernameMaxLength else {
            return .failure(.usernameTooLong(limit: usernameMaxLength))
        }
        guard trimmed.range(of: usernamePattern, options: .regularExpression) != nil else {
            return .failure(.usernameInvalidCharacters)
        }
        guard !existingUsernames.contains(trimmed) else {
            return .failure(.usernameTaken)
        }
        return .success(trimmed)
    }
}
