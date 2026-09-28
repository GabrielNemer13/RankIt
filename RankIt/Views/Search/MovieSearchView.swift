import SwiftUI

struct MovieSearchView: View {
    let currentUser: User

    @Environment(\.movieCatalogService) private var catalogService
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: MovieSearchViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    SearchResultsList(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Search")
        }
        .task {
            if viewModel == nil {
                viewModel = MovieSearchViewModel(catalogService: catalogService, currentUser: currentUser, modelContext: modelContext)
            }
        }
    }
}

private struct SearchResultsList: View {
    @Bindable var viewModel: MovieSearchViewModel
    @State private var selectedMovie: Movie?
    @Environment(\.dismissSearch) private var dismissSearch

    private var trimmedQuery: String {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                emptyQueryState
            } else {
                searchResultsState
            }
        }
        .searchable(text: $viewModel.query, prompt: "Search movies")
        .scrollDismissesKeyboard(.immediately)
        .task(id: viewModel.query) {
            await viewModel.search()
        }
        .task {
            await viewModel.loadTrendingIfNeeded()
        }
        .navigationDestination(item: $selectedMovie) { movie in
            TierPickerView(movie: movie)
        }
    }

    // MARK: - Empty query: recent searches + trending

    @ViewBuilder
    private var emptyQueryState: some View {
        if !viewModel.recentSearches.isEmpty {
            Section {
                ForEach(viewModel.recentSearches, id: \.self) { recent in
                    Button {
                        viewModel.selectRecentSearch(recent)
                    } label: {
                        Label(recent, systemImage: "clock")
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                HStack {
                    Text("Recent Searches")
                    Spacer()
                    Button("Clear") {
                        viewModel.clearRecentSearches()
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            }
        }

        Section {
            if viewModel.isLoadingTrending, viewModel.trendingMovies.isEmpty {
                loadingRow
            } else if let trendingErrorMessage = viewModel.trendingErrorMessage, viewModel.trendingMovies.isEmpty {
                ErrorStateRow(message: trendingErrorMessage) {
                    Task { await viewModel.retryTrending() }
                }
            } else if viewModel.trendingMovies.isEmpty {
                Text("Search for a movie to get started.")
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.trendingMovies) { movie in
                    resultRow(for: movie)
                        .onAppear { viewModel.loadMoreTrendingIfNeeded(currentMovie: movie) }
                }
                if viewModel.isLoadingMoreTrending {
                    loadingRow
                }
            }
        } header: {
            Text("Trending")
        }
    }

    // MARK: - Non-empty query: loading / error / no-results / results

    @ViewBuilder
    private var searchResultsState: some View {
        if viewModel.isSearching, viewModel.results.isEmpty {
            loadingRow
        } else if let errorMessage = viewModel.searchErrorMessage {
            ErrorStateRow(message: errorMessage) {
                Task { await viewModel.retrySearch() }
            }
        } else if viewModel.results.isEmpty {
            Text("No results for \"\(viewModel.query)\"")
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)
        } else {
            ForEach(viewModel.results) { movie in
                resultRow(for: movie)
                    .onAppear { viewModel.loadMoreResultsIfNeeded(currentMovie: movie) }
            }
            if viewModel.isLoadingMoreResults {
                loadingRow
            }
        }
    }

    private var loadingRow: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
    }

    private func resultRow(for movie: Movie) -> some View {
        Button {
            dismissSearch()
            viewModel.recordSelection()
            selectedMovie = movie
        } label: {
            SearchResultRow(movie: movie, loggedTier: viewModel.loggedTiers[movie.tmdbID])
        }
        .buttonStyle(.plain)
    }
}

private struct ErrorStateRow: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
    }
}

/// Poster/title/year/rating via the shared `MoviePosterRow` (same as
/// Library and Watchlist rows), plus an "already logged" tier badge when
/// applicable. Tapping still logs a fresh `LoggedMovie` as a rewatch --
/// `LogFlowViewModel` already supports that by design, so the badge is
/// purely informational and doesn't change tap behavior.
private struct SearchResultRow: View {
    let movie: Movie
    let loggedTier: MovieTier?

    var body: some View {
        HStack(spacing: 8) {
            MoviePosterRow(movie: movie)
            if let loggedTier {
                TierBadge(tier: loggedTier)
            }
        }
    }
}

private struct TierBadge: View {
    let tier: MovieTier

    var body: some View {
        Text("\(tier.emoji) \(tier.rawValue.capitalized)")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}

#Preview {
    MovieSearchView(currentUser: User(username: "preview", displayName: "Preview"))
        .environment(\.movieCatalogService, PreviewMovieCatalogService())
        .modelContainer(for: [
            User.self, Movie.self, LoggedMovie.self, ComparisonEvent.self,
            Watchlist.self, Follow.self, ActivityFeedItem.self, Trailer.self,
            DiscoverInteraction.self
        ], inMemory: true)
}
