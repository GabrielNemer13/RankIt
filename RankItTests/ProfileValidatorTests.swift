import XCTest
@testable import RankIt

final class ProfileValidatorTests: XCTestCase {

    // MARK: - Display name

    func test_displayName_rejectsEmpty() {
        assertFailure(ProfileValidator.validateDisplayName(""), .displayNameEmpty)
    }

    func test_displayName_rejectsWhitespaceOnly() {
        assertFailure(ProfileValidator.validateDisplayName("   "), .displayNameEmpty)
    }

    func test_displayName_trimsWhitespace() {
        assertSuccess(ProfileValidator.validateDisplayName("  Jamie Rivera  "), "Jamie Rivera")
    }

    func test_displayName_rejectsTooLong() {
        let tooLong = String(repeating: "a", count: ProfileValidator.displayNameMaxLength + 1)
        assertFailure(ProfileValidator.validateDisplayName(tooLong), .displayNameTooLong(limit: ProfileValidator.displayNameMaxLength))
    }

    func test_displayName_acceptsExactlyAtLimit() {
        let atLimit = String(repeating: "a", count: ProfileValidator.displayNameMaxLength)
        assertSuccess(ProfileValidator.validateDisplayName(atLimit), atLimit)
    }

    // MARK: - Username

    func test_username_rejectsEmpty() {
        assertFailure(ProfileValidator.validateUsername("", existingUsernames: []), .usernameEmpty)
    }

    func test_username_rejectsWhitespaceOnly() {
        assertFailure(ProfileValidator.validateUsername("   ", existingUsernames: []), .usernameEmpty)
    }

    func test_username_trimsWhitespace() {
        assertSuccess(ProfileValidator.validateUsername("  jamie_r  ", existingUsernames: []), "jamie_r")
    }

    func test_username_rejectsUppercase() {
        assertFailure(ProfileValidator.validateUsername("Jamie", existingUsernames: []), .usernameInvalidCharacters)
    }

    func test_username_rejectsSpaces() {
        assertFailure(ProfileValidator.validateUsername("jamie rivera", existingUsernames: []), .usernameInvalidCharacters)
    }

    func test_username_rejectsSymbols() {
        assertFailure(ProfileValidator.validateUsername("jamie-r!", existingUsernames: []), .usernameInvalidCharacters)
    }

    func test_username_acceptsLowercaseNumbersAndUnderscores() {
        assertSuccess(ProfileValidator.validateUsername("jamie_r_2", existingUsernames: []), "jamie_r_2")
    }

    func test_username_rejectsTooLong() {
        let tooLong = String(repeating: "a", count: ProfileValidator.usernameMaxLength + 1)
        assertFailure(ProfileValidator.validateUsername(tooLong, existingUsernames: []), .usernameTooLong(limit: ProfileValidator.usernameMaxLength))
    }

    func test_username_acceptsExactlyAtLimit() {
        let atLimit = String(repeating: "a", count: ProfileValidator.usernameMaxLength)
        assertSuccess(ProfileValidator.validateUsername(atLimit, existingUsernames: []), atLimit)
    }

    func test_username_rejectsDuplicateAgainstLocalUser() {
        assertFailure(ProfileValidator.validateUsername("taken", existingUsernames: ["taken"]), .usernameTaken)
    }

    func test_username_duplicateCheckIsExactMatchAgainstProvidedSet() {
        // The validator does a plain exact-match check against whatever
        // set it's given -- callers (ProfileEditViewModel.otherUsernames)
        // are responsible for lowercasing that set first, since usernames
        // are constrained to lowercase but the set itself isn't normalized
        // here.
        assertFailure(ProfileValidator.validateUsername("taken", existingUsernames: ["taken"]), .usernameTaken)
        assertSuccess(ProfileValidator.validateUsername("taken", existingUsernames: ["TAKEN"]), "taken")
    }

    func test_username_allowsSameNameNotInExistingSet() {
        // Simulates editing your own profile: your own current username is
        // excluded from the set by the caller, so re-saving it unchanged
        // must not falsely flag as taken.
        assertSuccess(ProfileValidator.validateUsername("me", existingUsernames: ["someoneelse"]), "me")
    }

    // MARK: - Helpers

    private func assertSuccess(_ result: Result<String, ProfileValidationError>, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .success(let value): XCTAssertEqual(value, expected, file: file, line: line)
        case .failure(let error): XCTFail("expected success but got \(error)", file: file, line: line)
        }
    }

    private func assertFailure(_ result: Result<String, ProfileValidationError>, _ expected: ProfileValidationError, file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .success(let value): XCTFail("expected failure \(expected) but got success(\(value))", file: file, line: line)
        case .failure(let error): XCTAssertEqual(error, expected, file: file, line: line)
        }
    }
}
