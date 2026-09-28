import SwiftUI
import SwiftData

enum AppTab {
    case search, library, discover, friends, watchlist
}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentUser: User?
    @State private var selectedTab: AppTab = .discover

    var body: some View {
        Group {
            if let currentUser {
                if hasCompletedOnboarding {
                    TabView(selection: $selectedTab) {
                        MovieSearchView(currentUser: currentUser)
                            .tabItem { Label("Search", systemImage: "magnifyingglass") }
                            .tag(AppTab.search)

                        NavigationStack {
                            LibraryView(userID: currentUser.id)
                        }
                        .tabItem { Label("Library", systemImage: "books.vertical") }
                        .tag(AppTab.library)

                        DiscoverView(currentUser: currentUser)
                            .tabItem { Label("Discover", systemImage: "play.rectangle.on.rectangle") }
                            .tag(AppTab.discover)

                        FriendsView(currentUser: currentUser)
                            .tabItem { Label("Friends", systemImage: "person.2") }
                            .tag(AppTab.friends)

                        WatchlistView(userID: currentUser.id)
                            .tabItem { Label("Watchlist", systemImage: "bookmark") }
                            .tag(AppTab.watchlist)
                    }
                } else {
                    OnboardingView(currentUser: currentUser) { startingTab in
                        if let startingTab { selectedTab = startingTab }
                        hasCompletedOnboarding = true
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            if currentUser == nil {
                // Must check this *before* fetchOrCreateCurrentUser, which
                // would otherwise create a row and make it always true.
                let userAlreadyExisted = CurrentUserProvider.hasExistingUser(in: modelContext)
                currentUser = CurrentUserProvider.fetchOrCreateCurrentUser(in: modelContext)
                if !OnboardingGate.shouldShowOnboarding(userAlreadyExisted: userAlreadyExisted, hasCompletedOnboarding: hasCompletedOnboarding) {
                    // Either already completed, or an existing install from
                    // before onboarding existed -- never force the latter
                    // through onboarding retroactively.
                    hasCompletedOnboarding = true
                }
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.movieCatalogService, PreviewMovieCatalogService())
        .modelContainer(for: [
            User.self, Movie.self, LoggedMovie.self, ComparisonEvent.self,
            Watchlist.self, Follow.self, ActivityFeedItem.self, Trailer.self,
            DiscoverInteraction.self
        ], inMemory: true)
}
