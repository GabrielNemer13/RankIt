import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class MovieSearchViewModel {
    var query: String = ""
    private(set) var results: [Movie] = []
    private(set) var isSearching = false
    private(set) var searchErrorMessage: String?

    private(set) var trendingMovies: [Movie] = []
    private(set) var isLoadingTrending = false
    private(set) var trendingErrorMessage: String?

    private(set) var recentSearches: [String] = []

    private let catalogService: any MovieCatalogServicing
    private let currentUser: User
    private let modelContext: ModelContext
    private let recentSearchesStore: RecentSearchesStore

    /// Bumped on every `search()` call and captured locally as `generation`.
    /// A response only gets applied if `generation` still matches this by
    /// the time it comes back -- independent of (and in addition to)
    /// `Task` cancellation, so a slower, now-stale response can never
    /// clobber a faster, newer one no matter how the two overlap.
    private var searchGeneration = 0

    init(
        catalogService: any MovieCatalogServicing,
        currentUser: User,
        modelContext: ModelContext,
        recentSearchesStore: RecentSearchesStore = RecentSearchesStore()
    ) {
        self.catalogService = catalogService
        self.currentUser = currentUser
        self.modelContext = modelContext
        self.recentSearchesStore = recentSearchesStore
        self.recentSearches = recentSearchesStore.queries
    }

    /// Movie IDs the current user has already logged, mapped to the tier
    /// of their most recent log (rewatches are valid by design -- see
    /// `LoggedMovie` -- so this just picks the newest one for the badge).
    /// Computed fresh on each access rather than cached, since it can
    /// change any time the user logs something else.
    var loggedTiers: [Int: MovieTier] {
        let userID = currentUser.id
        let descriptor = FetchDescriptor<LoggedMovie>(predicate: #Predicate<LoggedMovie> { $0.userID == userID })
        let rows = ((try? modelContext.fetch(descriptor)) ?? []).sorted { $0.watchedDate > $1.watchedDate }
        var result: [Int: MovieTier] = [:]
        for row in rows where result[row.movieID] == nil {
            result[row.movieID] = row.tier
        }
        return result
    }

    func loadTrendingIfNeeded() async {
        guard trendingMovies.isEmpty, !isLoadingTrending else { return }
        await loadTrending()
    }

    func retryTrending() async {
        await loadTrending()
    }

    private func loadTrending() async {
        isLoadingTrending = true
        trendingErrorMessage = nil
        defer { isLoadingTrending = false }
        do {
            trendingMovies = try await catalogService.trending()
        } catch {
            trendingMovies = []
            trendingErrorMessage = error.localizedDescription
        }
    }

    /// Debounced search driven by `.task(id: query)` in the view — SwiftUI
    /// cancels the in-flight task automatically whenever `query` changes
    /// again before this completes. The `searchGeneration` check below is
    /// an independent second guard against the same problem (see its doc).
    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration += 1
        let generation = searchGeneration

        guard !trimmed.isEmpty else {
            results = []
            searchErrorMessage = nil
            isSearching = false
            return
        }

        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            return // superseded by a newer keystroke
        }
        guard generation == searchGeneration, !Task.isCancelled else { return }

        isSearching = true
        searchErrorMessage = nil
        defer {
            // Only the current generation gets to clear the spinner --
            // otherwise a slow, now-superseded call could flip it back to
            // false right as the real (newer) search is still in flight.
            if generation == searchGeneration { isSearching = false }
        }
        do {
            let movies = try await catalogService.searchMovies(query: trimmed)
            guard generation == searchGeneration else { return } // superseded
            results = movies
        } catch {
            guard generation == searchGeneration else { return } // superseded
            results = []
            searchErrorMessage = error.localizedDescription
        }
    }

    func retrySearch() async {
        await search()
    }

    /// Adds the current query to recent searches. Only called when the user
    /// actually opens a result (see `MovieSearchView`), never on every
    /// keystroke -- and it's a no-op for an empty query, which covers
    /// selecting a movie from the trending landing state.
    func recordSelection() {
        recentSearchesStore.record(query)
        recentSearches = recentSearchesStore.queries
    }

    func selectRecentSearch(_ recent: String) {
        query = recent
    }

    func clearRecentSearches() {
        recentSearchesStore.clear()
        recentSearches = []
    }
}
