import XCTest
import SwiftData
@testable import RankIt

@MainActor
final class ProfileEditViewModelTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            User.self, Movie.self, LoggedMovie.self, ComparisonEvent.self,
            Watchlist.self, Follow.self, ActivityFeedItem.self, Trailer.self,
            DiscoverInteraction.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
    }

    func test_save_updatesExistingUser_withoutCreatingASecondRow() {
        let user = CurrentUserProvider.fetchOrCreateCurrentUser(in: modelContext)
        let originalID = user.id
        let viewModel = ProfileEditViewModel(user: user, modelContext: modelContext)

        viewModel.displayName = "Jamie Rivera"
        viewModel.username = "jamie_r"
        let saved = viewModel.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(user.id, originalID, "must update the same row, not swap it for a new one")
        XCTAssertEqual(user.displayName, "Jamie Rivera")
        XCTAssertEqual(user.username, "jamie_r")

        let allUsers = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        XCTAssertEqual(allUsers.count, 1, "profile creation must not duplicate the placeholder User row")
    }

    func test_save_trimsAndLowercasesBeforePersisting() {
        let user = CurrentUserProvider.fetchOrCreateCurrentUser(in: modelContext)
        let viewModel = ProfileEditViewModel(user: user, modelContext: modelContext)

        viewModel.displayName = "  Jamie Rivera  "
        viewModel.username = "  jamie_r  "
        XCTAssertTrue(viewModel.save())

        XCTAssertEqual(user.displayName, "Jamie Rivera")
        XCTAssertEqual(user.username, "jamie_r")
    }

    func test_save_failsAndDoesNotMutate_onInvalidUsername() {
        let user = CurrentUserProvider.fetchOrCreateCurrentUser(in: modelContext)
        let originalUsername = user.username
        let viewModel = ProfileEditViewModel(user: user, modelContext: modelContext)

        viewModel.displayName = "Jamie Rivera"
        viewModel.username = "Not Valid!"
        let saved = viewModel.save()

        XCTAssertFalse(saved)
        XCTAssertEqual(user.username, originalUsername, "an invalid save must leave the stored user untouched")
        XCTAssertNotNil(viewModel.usernameError)
    }

    func test_save_failsWhenUsernameTakenByAnotherLocalUser() {
        // Create the current user first, while the store is still empty --
        // fetchOrCreateCurrentUser's fetch-first logic would otherwise
        // pick up "other" below as if it were the current user.
        let user = CurrentUserProvider.fetchOrCreateCurrentUser(in: modelContext)
        let other = User(username: "taken", displayName: "Other")
        modelContext.insert(other)
        let viewModel = ProfileEditViewModel(user: user, modelContext: modelContext)

        viewModel.displayName = "Jamie Rivera"
        viewModel.username = "taken"

        XCTAssertFalse(viewModel.save())
        XCTAssertEqual(viewModel.usernameError, ProfileValidationError.usernameTaken.errorDescription)
    }

    func test_save_allowsKeepingYourOwnCurrentUsernameUnchanged() {
        let user = CurrentUserProvider.fetchOrCreateCurrentUser(in: modelContext) // username "me"
        let viewModel = ProfileEditViewModel(user: user, modelContext: modelContext)

        viewModel.displayName = "Me"
        viewModel.username = "me"

        XCTAssertTrue(viewModel.save(), "saving your own unchanged username must not be flagged as taken")
    }

    func test_isValid_reflectsCurrentFieldState() {
        let user = CurrentUserProvider.fetchOrCreateCurrentUser(in: modelContext)
        let viewModel = ProfileEditViewModel(user: user, modelContext: modelContext)

        viewModel.displayName = ""
        XCTAssertFalse(viewModel.isValid)

        viewModel.displayName = "Jamie"
        viewModel.username = "jamie"
        XCTAssertTrue(viewModel.isValid)
    }
}
