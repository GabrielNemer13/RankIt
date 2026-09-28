import SwiftUI
import SwiftData

/// Shows one user's ranked movies, grouped by tier and ordered by
/// rank_position (with the watchedDate tiebreak baked into `queryOrder`).
/// Parameterized by `userID` so it doubles as the read-only view of a
/// followed friend's library (see FriendsView).
struct LibraryView: View {
    let userID: UUID
    let navigationTitle: String
    /// True only for the signed-in user's own Library tab. False when this
    /// view is reused read-only for a followed user (see FriendsView) —
    /// in that case rows never offer a destructive action.
    let isOwnLibrary: Bool

    @Query private var loggedMovies: [LoggedMovie]
    @Query private var movies: [Movie]

    init(userID: UUID, navigationTitle: String = "Library", isOwnLibrary: Bool = true) {
        self.userID = userID
        self.navigationTitle = navigationTitle
        self.isOwnLibrary = isOwnLibrary
        _loggedMovies = Query(
            filter: #Predicate<LoggedMovie> { $0.userID == userID },
            sort: LoggedMovie.queryOrder
        )
        // Movie is cached, shared reference data (not scoped per-user), so
        // it's fetched unfiltered and joined to LoggedMovie by tmdbID below.
        _movies = Query()
    }

    private static let tierDisplayOrder: [MovieTier] = [.loved, .liked, .disliked]

    private var moviesByID: [Int: Movie] {
        Dictionary(uniqueKeysWithValues: movies.map { ($0.tmdbID, $0) })
    }

    private var sections: [(tier: MovieTier, entries: [LoggedMovie])] {
        let byTier = Dictionary(grouping: loggedMovies, by: \.tier)
        return Self.tierDisplayOrder.compactMap { tier in
            guard let entries = byTier[tier], !entries.isEmpty else { return nil }
            return (tier, entries)
        }
    }

    var body: some View {
        Group {
            if loggedMovies.isEmpty {
                ContentUnavailableView(
                    "No movies logged yet",
                    systemImage: "film",
                    description: Text("Movies logged here will show up ranked within each tier.")
                )
            } else {
                List {
                    ForEach(sections, id: \.tier) { section in
                        Section {
                            ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, logged in
                                let movie = moviesByID[logged.movieID]
                                if let movie {
                                    NavigationLink {
                                        MovieDetailView(
                                            movie: movie,
                                            context: .forLibraryRow(loggedMovie: logged, isOwnLibrary: isOwnLibrary)
                                        )
                                    } label: {
                                        LibraryRow(rank: index + 1, movie: movie)
                                    }
                                } else {
                                    LibraryRow(rank: index + 1, movie: nil)
                                }
                            }
                        } header: {
                            Text("\(section.tier.emoji) \(section.tier.rawValue.capitalized)")
                        }
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
    }
}

private struct LibraryRow: View {
    let rank: Int
    let movie: Movie?

    var body: some View {
        MoviePosterRow(movie: movie) {
            Text("#\(rank)")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
        }
    }
}
