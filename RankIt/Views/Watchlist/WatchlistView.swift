import SwiftUI
import SwiftData

/// Movies the signed-in user added to their Watchlist from Discover, most
/// recently added first. Reuses Library's row styling; tapping a row opens
/// the same read-only `MovieDetailView`.
struct WatchlistView: View {
    let userID: UUID

    @Query private var watchlistEntries: [Watchlist]
    @Query private var movies: [Movie]

    init(userID: UUID) {
        self.userID = userID
        _watchlistEntries = Query(
            filter: #Predicate<Watchlist> { $0.userID == userID },
            sort: [SortDescriptor(\Watchlist.addedDate, order: .reverse)]
        )
        _movies = Query()
    }

    private var moviesByID: [Int: Movie] {
        Dictionary(uniqueKeysWithValues: movies.map { ($0.tmdbID, $0) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if watchlistEntries.isEmpty {
                    ContentUnavailableView(
                        "Nothing on your watchlist",
                        systemImage: "bookmark",
                        description: Text("Movies you save from Discover will show up here.")
                    )
                } else {
                    List(watchlistEntries) { entry in
                        let movie = moviesByID[entry.movieID]
                        if let movie {
                            NavigationLink {
                                MovieDetailView(movie: movie, context: .watchlist(entry: entry))
                            } label: {
                                MoviePosterRow(movie: movie)
                            }
                        } else {
                            MoviePosterRow(movie: nil)
                        }
                    }
                }
            }
            .navigationTitle("Watchlist")
        }
    }
}
