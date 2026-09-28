import SwiftUI
import SwiftData

/// Friends tab: lands on the Activity feed (your own + followed users'
/// actions); typing in the search bar switches to a user search so you can
/// follow people; "Following" opens the list of who you follow (and, from
/// there, their read-only libraries).
///
/// Activity was folded in here rather than given its own 6th tab: iOS only
/// shows 5 tabs directly and collapses anything beyond that into a "More"
/// list, which would have buried the existing Watchlist tab -- a
/// discoverability regression for an already-shipped feature. Search for
/// other users and follow them (one-directional, no request/accept state —
/// see SPEC.md's open question on the social graph model). Following is
/// purely local SwiftData for now; multi-user sync is a later problem.
struct FriendsView: View {
    let currentUser: User

    @Query private var allUsers: [User]
    @Query private var follows: [Follow]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var showingFollowingList = false
    @State private var showingEditProfile = false

    init(currentUser: User) {
        self.currentUser = currentUser
        let userID = currentUser.id
        _allUsers = Query(sort: [SortDescriptor(\User.username)])
        _follows = Query(filter: #Predicate<Follow> { $0.followerID == userID })
    }

    private var followeeIDs: Set<UUID> {
        Set(follows.map(\.followeeID))
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [User] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return allUsers.filter { user in
            user.id != currentUser.id &&
            (user.username.localizedCaseInsensitiveContains(trimmed) ||
             user.displayName.localizedCaseInsensitiveContains(trimmed))
        }
    }

    private var followedUsers: [User] {
        allUsers.filter { followeeIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    List {
                        Section("Results") {
                            if searchResults.isEmpty {
                                Text("No users found").foregroundStyle(.secondary)
                            }
                            ForEach(searchResults) { user in
                                SearchResultRow(
                                    user: user,
                                    isFollowing: followeeIDs.contains(user.id),
                                    onToggleFollow: { toggleFollow(user) }
                                )
                            }
                        }
                    }
                } else {
                    ActivityFeedView(currentUser: currentUser)
                }
            }
            .searchable(text: $searchText, prompt: "Search users")
            .navigationTitle(isSearching ? "Friends" : "Activity")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFollowingList = true
                    } label: {
                        Label("Following", systemImage: "person.2")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditProfile = true
                    } label: {
                        Label("Edit Profile", systemImage: "person.crop.circle")
                    }
                }
            }
            .sheet(isPresented: $showingFollowingList) {
                FollowingListSheet(followedUsers: followedUsers, onUnfollow: toggleFollow)
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileSheet(user: currentUser)
            }
        }
    }

    private func toggleFollow(_ user: User) {
        if let existing = follows.first(where: { $0.followeeID == user.id }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(Follow(followerID: currentUser.id, followeeID: user.id))
        }
        try? modelContext.save()
    }
}

private struct FollowingListSheet: View {
    let followedUsers: [User]
    let onUnfollow: (User) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if followedUsers.isEmpty {
                    Text("You're not following anyone yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(followedUsers) { user in
                    NavigationLink {
                        LibraryView(userID: user.id, navigationTitle: user.displayName, isOwnLibrary: false)
                    } label: {
                        UserRow(user: user)
                    }
                    .swipeActions {
                        Button("Unfollow", role: .destructive) {
                            onUnfollow(user)
                        }
                    }
                }
            }
            .navigationTitle("Following")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct UserRow: View {
    let user: User

    var body: some View {
        VStack(alignment: .leading) {
            Text(user.displayName).font(.headline)
            Text("@\(user.username)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SearchResultRow: View {
    let user: User
    let isFollowing: Bool
    let onToggleFollow: () -> Void

    var body: some View {
        HStack {
            UserRow(user: user)
            Spacer()
            Button(isFollowing ? "Following" : "Follow") {
                onToggleFollow()
            }
            .buttonStyle(.bordered)
            .tint(isFollowing ? .secondary : .accentColor)
        }
    }
}
