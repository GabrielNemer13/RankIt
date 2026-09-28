import SwiftUI
import SwiftData

/// What screen `MovieDetailView` was reached from, and therefore what (if
/// anything) it's allowed to delete. Only the current user's own Library or
/// Watchlist rows get a destructive action; everything else — including a
/// followed user's library, reached via `LibraryView(userID:)` — is
/// strictly read-only.
enum MovieDetailContext: Equatable {
    case library(loggedMovie: LoggedMovie)
    case watchlist(entry: Watchlist)
    case readOnly

    /// The single seam that decides whether a Library row is editable: a
    /// followed user's library (`isOwnLibrary == false`) is always
    /// read-only, regardless of what row it is. See `LibraryView`.
    static func forLibraryRow(loggedMovie: LoggedMovie, isOwnLibrary: Bool) -> MovieDetailContext {
        isOwnLibrary ? .library(loggedMovie: loggedMovie) : .readOnly
    }

    var loggedMovie: LoggedMovie? {
        if case .library(let loggedMovie) = self { return loggedMovie }
        return nil
    }
}

/// Movie detail — synopsis, cast, genres, and (depending on `context`) a
/// destructive removal action. Reached from Library and Watchlist rows. If
/// the cached `Movie` is missing cast/synopsis (common for movies cached
/// from search/trending, which don't return credits), lazily fetches full
/// details and backfills the persisted Movie.
struct MovieDetailView: View {
    let movie: Movie
    var context: MovieDetailContext = .readOnly

    @Environment(\.movieCatalogService) private var catalogService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingDetails = false
    @State private var loadErrorMessage: String?
    @State private var showingRemoveConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: movie.posterURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(movie.title)
                        .font(.title2.bold())

                    HStack(spacing: 8) {
                        if movie.year > 0 {
                            Text(String(movie.year))
                        }
                        if movie.voteAverage > 0 {
                            Label(String(format: "%.1f", movie.voteAverage), systemImage: "star.fill")
                        }
                        if let runtimeMinutes = movie.runtimeMinutes {
                            Text("\(runtimeMinutes) min")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                if !movie.genres.isEmpty {
                    Text(movie.genres.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !movie.overview.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Synopsis").font(.headline)
                        Text(movie.overview)
                    }
                }

                if !movie.cast.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cast").font(.headline)
                        Text(movie.cast.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                } else if isLoadingDetails {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let loadErrorMessage {
                    Text(loadErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let loggedMovie = context.loggedMovie {
                    VStack(spacing: 12) {
                        if actions.canViewComparisonHistory {
                            NavigationLink {
                                ComparisonHistoryView(loggedMovie: loggedMovie, movieTitle: movie.title)
                            } label: {
                                Label("Comparison History", systemImage: "clock.arrow.circlepath")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .foregroundStyle(.primary)
                        }

                        if actions.canReRank {
                            NavigationLink {
                                ComparisonView(movie: movie, tier: loggedMovie.tier, reRankingExisting: loggedMovie)
                            } label: {
                                Label("Re-rank this movie", systemImage: "arrow.up.arrow.down")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .foregroundStyle(.primary)
                        }

                        if actions.canChangeTier {
                            NavigationLink {
                                ChangeTierView(movie: movie, loggedMovie: loggedMovie)
                            } label: {
                                Label("Change Tier", systemImage: "arrow.left.arrow.right")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    .padding(.top, 8)
                }

                if let removeButtonTitle = actions.removeButtonTitle {
                    Button(role: .destructive) {
                        showingRemoveConfirmation = true
                    } label: {
                        Text(removeButtonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
            }
            .padding()
        }
        .navigationTitle(movie.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetailsIfNeeded()
        }
        .alert(
            removeConfirmationTitle,
            isPresented: $showingRemoveConfirmation
        ) {
            Button("Remove", role: .destructive) { performRemove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removeConfirmationMessage)
        }
    }

    private var actions: DetailActions { DetailActions.available(for: context) }

    private var removeConfirmationTitle: String {
        switch context {
        case .library: return "Remove from Library?"
        case .watchlist: return "Remove from Watchlist?"
        case .readOnly: return ""
        }
    }

    private var removeConfirmationMessage: String {
        switch context {
        case .library:
            return "This removes \(movie.title) from your Library, including its rank. This can't be undone."
        case .watchlist:
            return "This removes \(movie.title) from your Watchlist. This can't be undone."
        case .readOnly:
            return ""
        }
    }

    private func performRemove() {
        switch context {
        case .library(let loggedMovie):
            // Deleting just removes this row -- rank_position is a relative
            // ordering key (each insertion shifts by exactly one to open a
            // slot), not a dense 0..n sequence, so leaving a gap here is
            // safe and doesn't require renumbering the rest of the tier.
            modelContext.delete(loggedMovie)
        case .watchlist(let entry):
            modelContext.delete(entry)
        case .readOnly:
            return
        }
        try? modelContext.save()
        dismiss()
    }

    private func loadDetailsIfNeeded() async {
        guard movie.overview.isEmpty || movie.cast.isEmpty else { return }
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        do {
            let detailed = try await catalogService.movieDetails(id: movie.tmdbID)
            movie.overview = detailed.overview
            movie.cast = detailed.cast
            if movie.runtimeMinutes == nil { movie.runtimeMinutes = detailed.runtimeMinutes }
            if movie.director == nil { movie.director = detailed.director }
            if movie.voteAverage == 0 { movie.voteAverage = detailed.voteAverage }
            try? modelContext.save()
        } catch {
            loadErrorMessage = "Couldn't load more details."
        }
    }
}
