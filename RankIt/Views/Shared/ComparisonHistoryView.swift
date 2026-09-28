import SwiftUI
import SwiftData

/// Shows a movie's head-to-head comparison history within its tier: which
/// movies it was directly compared against, and whether it won, lost, or
/// tied. Reached only from the current user's own Library (see
/// MovieDetailContext.library).
struct ComparisonHistoryView: View {
    let loggedMovie: LoggedMovie
    let movieTitle: String

    @Environment(\.modelContext) private var modelContext
    @State private var currentUser: User?

    var body: some View {
        Group {
            if let currentUser {
                ComparisonHistoryContent(loggedMovie: loggedMovie, currentUser: currentUser, movieTitle: movieTitle)
            } else {
                ProgressView()
            }
        }
        .task {
            if currentUser == nil {
                currentUser = CurrentUserProvider.fetchOrCreateCurrentUser(in: modelContext)
            }
        }
    }
}

private struct ComparisonHistoryContent: View {
    let loggedMovie: LoggedMovie
    let currentUser: User
    let movieTitle: String

    @Query private var events: [ComparisonEvent]
    @Query private var movies: [Movie]

    init(loggedMovie: LoggedMovie, currentUser: User, movieTitle: String) {
        self.loggedMovie = loggedMovie
        self.currentUser = currentUser
        self.movieTitle = movieTitle
        // Single-field predicate, filtered further client-side -- compound
        // predicates have proven unreliable elsewhere in this codebase.
        let userID = currentUser.id
        _events = Query(filter: #Predicate<ComparisonEvent> { $0.userID == userID })
        _movies = Query()
    }

    private var moviesByTmdbID: [Int: Movie] {
        Dictionary(uniqueKeysWithValues: movies.map { ($0.tmdbID, $0) })
    }

    private var relevantEvents: [ComparisonEvent] {
        let movieID = loggedMovie.movieID
        return events
            .filter { $0.movieAID == movieID || $0.movieBID == movieID }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        Group {
            if relevantEvents.isEmpty {
                ContentUnavailableView(
                    "No comparison history",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Head-to-head comparisons made while ranking \(movieTitle) will show up here.")
                )
            } else {
                List(relevantEvents) { event in
                    ComparisonHistoryRow(
                        event: event,
                        thisMovieID: loggedMovie.movieID,
                        opponentTitle: opponentTitle(for: event)
                    )
                }
            }
        }
        .navigationTitle("Comparison History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func opponentTitle(for event: ComparisonEvent) -> String {
        let movieID = loggedMovie.movieID
        let opponentID = event.movieAID == movieID ? event.movieBID : event.movieAID
        return moviesByTmdbID[opponentID]?.title ?? "Unknown movie"
    }
}

private struct ComparisonHistoryRow: View {
    let event: ComparisonEvent
    let thisMovieID: Int
    let opponentTitle: String

    private var outcomeText: String {
        guard let winnerID = event.winnerID else { return "Tied with" }
        return winnerID == thisMovieID ? "Won vs" : "Lost to"
    }

    private var outcomeColor: Color {
        guard let winnerID = event.winnerID else { return .secondary }
        return winnerID == thisMovieID ? .green : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(outcomeText) \(opponentTitle)")
                .foregroundStyle(outcomeColor)
            Text(event.timestamp, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
