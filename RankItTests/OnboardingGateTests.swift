import XCTest
import SwiftData
@testable import RankIt

final class OnboardingGateTests: XCTestCase {

    func test_freshInstall_showsOnboarding() {
        XCTAssertTrue(OnboardingGate.shouldShowOnboarding(userAlreadyExisted: false, hasCompletedOnboarding: false))
    }

    func test_afterCompletion_doesNotShowOnboardingAgain() {
        XCTAssertFalse(OnboardingGate.shouldShowOnboarding(userAlreadyExisted: false, hasCompletedOnboarding: true))
    }

    func test_existingUser_skipsOnboardingEvenIfFlagNotYetSet() {
        XCTAssertFalse(OnboardingGate.shouldShowOnboarding(userAlreadyExisted: true, hasCompletedOnboarding: false))
    }

    func test_existingUserWithFlagAlreadySet_stillSkips() {
        XCTAssertFalse(OnboardingGate.shouldShowOnboarding(userAlreadyExisted: true, hasCompletedOnboarding: true))
    }
}

@MainActor
final class CurrentUserProviderTests: XCTestCase {
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

    func test_hasExistingUser_falseBeforeAnyUserCreated() {
        XCTAssertFalse(CurrentUserProvider.hasExistingUser(in: modelContext))
    }

    func test_hasExistingUser_trueAfterFetchOrCreate() {
        CurrentUserProvider.fetchOrCreateCurrentUser(in: modelContext)
        XCTAssertTrue(CurrentUserProvider.hasExistingUser(in: modelContext))
    }

    func test_hasExistingUser_trueForPreexistingUser() {
        modelContext.insert(User(username: "already_here", displayName: "Already Here"))
        XCTAssertTrue(CurrentUserProvider.hasExistingUser(in: modelContext))
    }

    func test_fetchOrCreate_returnsSameUserOnSecondCall() {
        let first = CurrentUserProvider.fetchOrCreateCurrentUser(in: modelContext)
        let second = CurrentUserProvider.fetchOrCreateCurrentUser(in: modelContext)
        XCTAssertEqual(first.id, second.id)
        let allUsers = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        XCTAssertEqual(allUsers.count, 1, "fetchOrCreateCurrentUser must never create a second row")
    }
}
