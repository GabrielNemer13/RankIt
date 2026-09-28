import Foundation
import SwiftData
import Observation

/// A movie paired with the one trailer to show for it in the feed.
struct DiscoverCandidate: Identifiable, Equatable {
    let movie: Movie
    let trailer: Trailer?
    var id: Int { movie.tmdbID }
}

@MainActor
@Observable
final class DiscoverViewModel {
    private(set) var candidates: [DiscoverCandidate] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var selectedGenre: String?

    private let catalogService: any MovieCatalogServicing
    private let currentUser: User
    private let modelContext: ModelContext

    init(catalogService: any MovieCatalogServicing, currentUser: User, modelContext: ModelContext) {
        self.catalogService = catalogService
        self.currentUser = currentUser
        self.modelContext = modelContext
    }

    /// Genres present in the current candidate set, for the filter menu.
    var availableGenres: [String] {
        Array(Set(candidates.flatMap(\.movie.genres))).sorted()
    }

    var visibleCandidates: [DiscoverCandidate] {
        guard let selectedGenre else { return candidates }
        return candidates.filter { $0.movie.genres.contains(selectedGenre) }
    }

    func loadIfNeeded() async {
        guard candidates.isEmpty, !isLoading else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // TODO: once trending is exhausted (or as a richer fallback),
            // broaden to another TMDb source — e.g. `discover/movie`
            // weighted toward genres the user ranks highly — and replace
            // this raw trending order with a real recommendation ranking.
            let trending = try await catalogService.trending()
            let loggedMovieIDs = Set(fetchLoggedMovieIDs())
            let unseen = trending.filter { !loggedMovieIDs.contains($0.tmdbID) }

            var built: [DiscoverCandidate] = []
            for movie in unseen {
                let trailers = (try? await catalogService.officialTrailers(movieID: movie.tmdbID)) ?? []
                let trailer = trailers.first(where: { $0.type == .trailer }) ?? trailers.first
                built.append(DiscoverCandidate(movie: movie, trailer: trailer))
            }
            candidates = built
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Records the interaction and, for `.watchlisted`, adds the movie to
    /// the user's Watchlist (deduped — repeated likes of the same movie
    /// shouldn't create duplicate Watchlist rows).
    func record(action: DiscoverAction, for candidate: DiscoverCandidate) {
        let interaction = DiscoverInteraction(userID: currentUser.id, movieID: candidate.movie.tmdbID, action: action)
        modelContext.insert(interaction)

        if action == .watchlisted, !isAlreadyOnWatchlist(movieID: candidate.movie.tmdbID) {
            // Candidates from trending() are never persisted on their own —
            // cache the Movie now so Watchlist (and anything else joining by
            // tmdbID) can actually resolve it later, instead of just storing
            // a dangling movieID.
            upsertMovie(candidate.movie)
            let watchlistEntry = Watchlist(userID: currentUser.id, movieID: candidate.movie.tmdbID)
            modelContext.insert(watchlistEntry)
            modelContext.insert(ActivityFeedItem(userID: currentUser.id, type: .watchlisted, refID: watchlistEntry.id))
        }

        try? modelContext.save()
    }

    private func isAlreadyOnWatchlist(movieID: Int) -> Bool {
        let userID = currentUser.id
        let descriptor = FetchDescriptor<Watchlist>(
            predicate: #Predicate<Watchlist> { $0.userID == userID && $0.movieID == movieID }
        )
        return !((try? modelContext.fetch(descriptor)) ?? []).isEmpty
    }

    @discardableResult
    private func upsertMovie(_ movie: Movie) -> Movie {
        let tmdbID = movie.tmdbID
        let descriptor = FetchDescriptor<Movie>(predicate: #Predicate<Movie> { $0.tmdbID == tmdbID })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            return existing
        }
        modelContext.insert(movie)
        return movie
    }

    private func fetchLoggedMovieIDs() -> [Int] {
        let userID = currentUser.id
        let descriptor = FetchDescriptor<LoggedMovie>(predicate: #Predicate<LoggedMovie> { $0.userID == userID })
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.movieID)
    }
}
