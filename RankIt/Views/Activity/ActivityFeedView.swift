import SwiftUI
import SwiftData

/// A combined feed of the current user's own actions plus their followed
/// users' actions, most recent first. There's no backend yet, so "followed
/// users" only ever means whatever `Follow` rows exist locally on this
/// device (see RankIt's CloudKit design notes) — this is expected for now,
/// not a bug.
struct ActivityFeedView: View {
    let currentUser: User

    @Query(sort: [SortDescriptor(\ActivityFeedItem.timestamp, order: .reverse)])
    private var allActivity: [ActivityFeedItem]
    @Query private var follows: [Follow]
    @Query private var allUsers: [User]
    @Query private var loggedMovies: [LoggedMovie]
    @Query private var watchlistEntries: [Watchlist]
    @Query private var movies: [Movie]

    init(currentUser: User) {
        self.currentUser = currentUser
        let userID = currentUser.id
        _follows = Query(filter: #Predicate<Follow> { $0.followerID == userID })
    }

    private var relevantUserIDs: Set<UUID> {
        Set(follows.map(\.followeeID)).union([currentUser.id])
    }

    private var visibleActivity: [ActivityFeedItem] {
        allActivity.filter { relevantUserIDs.contains($0.userID) }
    }

    private var usersByID: [UUID: User] {
        Dictionary(uniqueKeysWithValues: allUsers.map { ($0.id, $0) })
    }

    private var loggedMoviesByID: [UUID: LoggedMovie] {
        Dictionary(uniqueKeysWithValues: loggedMovies.map { ($0.id, $0) })
    }

    private var watchlistByID: [UUID: Watchlist] {
        Dictionary(uniqueKeysWithValues: watchlistEntries.map { ($0.id, $0) })
    }

    private var moviesByTmdbID: [Int: Movie] {
        Dictionary(uniqueKeysWithValues: movies.map { ($0.tmdbID, $0) })
    }

    /// No own `NavigationStack`/title -- this is embedded as the Friends
    /// tab's landing content (see FriendsView), which supplies both.
    var body: some View {
        Group {
            if visibleActivity.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "clock",
                    description: Text("Logging a movie, adding to your watchlist, or following someone will show up here.")
                )
            } else {
                List {
                    ForEach(visibleActivity) { item in
                        if let row = rowContent(for: item) {
                            ActivityRow(row: row)
                        }
                    }
                }
            }
        }
    }

    private func rowContent(for item: ActivityFeedItem) -> ActivityRowContent? {
        let isSelf = item.userID == currentUser.id
        let actorName = isSelf ? "You" : (usersByID[item.userID]?.displayName ?? "Someone")

        switch item.type {
        case .logged:
            guard let logged = loggedMoviesByID[item.refID],
                  let movie = moviesByTmdbID[logged.movieID] else { return nil }
            let rank = displayRank(for: logged)
            return ActivityRowContent(
                id: item.id,
                timestamp: item.timestamp,
                text: "\(actorName) logged \(movie.title) — \(logged.tier.rawValue.capitalized), #\(rank)"
            )
        case .watchlisted:
            guard let entry = watchlistByID[item.refID],
                  let movie = moviesByTmdbID[entry.movieID] else { return nil }
            let possessive = isSelf ? "your" : "their"
            return ActivityRowContent(
                id: item.id,
                timestamp: item.timestamp,
                text: "\(actorName) added \(movie.title) to \(possessive) watchlist"
            )
        case .reviewed, .followed:
            // Not wired up to any code path yet -- no data will ever
            // produce these cases today, but the switch must stay
            // exhaustive against future ActivityType additions.
            return nil
        }
    }

    /// The item's position within its owner's tier, matching Library's
    /// display order (rankPosition ascending, watchedDate descending for
    /// ties) -- not the raw stored `rankPosition` value, which can have
    /// gaps (see MovieDetailView's removal logic).
    private func displayRank(for loggedMovie: LoggedMovie) -> Int {
        let sameTier = loggedMovies
            .filter { $0.userID == loggedMovie.userID && $0.tier == loggedMovie.tier }
            .sorted(by: LoggedMovie.isOrderedForDisplay)
        return (sameTier.firstIndex(where: { $0.id == loggedMovie.id }) ?? 0) + 1
    }
}

private struct ActivityRowContent: Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
}

private struct ActivityRow: View {
    let row: ActivityRowContent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.text)
            Text(row.timestamp, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
