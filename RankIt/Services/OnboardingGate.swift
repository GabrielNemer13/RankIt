import Foundation

/// Pure decision logic for whether to show first-run onboarding, kept
/// separate from `RootTabView` so it's testable without SwiftUI.
enum OnboardingGate {
    /// - Parameters:
    ///   - userAlreadyExisted: whether a `User` row existed *before* this
    ///     launch resolved `currentUser` (see
    ///     `CurrentUserProvider.hasExistingUser`). An existing install from
    ///     before onboarding existed must never be forced through it.
    ///   - hasCompletedOnboarding: the persisted completion flag.
    static func shouldShowOnboarding(userAlreadyExisted: Bool, hasCompletedOnboarding: Bool) -> Bool {
        !userAlreadyExisted && !hasCompletedOnboarding
    }
}
