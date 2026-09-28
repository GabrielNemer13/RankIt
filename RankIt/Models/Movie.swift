import Foundation
import SwiftData

/// Cached TMDb data — not authored content. `tmdbID` is the canonical identifier
/// referenced by `movieID` fields across the rest of the model graph.
@Model
final class Movie {
    // No `.unique` -- CloudKit sync (planned) forbids it. Both call sites
    // that insert a Movie (LogFlowViewModel, DiscoverViewModel) already
    // fetch-by-tmdbID and reuse the existing row before inserting, so this
    // was never the actual dedup mechanism.
    var tmdbID: Int = 0
    var title: String = ""
    var year: Int = 0
    var posterURL: URL?
    var runtimeMinutes: Int?
    var director: String?
    var genres: [String] = []
    /// TMDb's own `vote_average`, 0–10 scale. Distinct from the signed-in
    /// user's personal tier/rank in `LoggedMovie`. Declared with an inline
    /// default (not just an init default) so SwiftData's lightweight
    /// migration can backfill this value on stores created before this
    /// property existed.
    var voteAverage: Double = 0
    /// TMDb's `overview` (synopsis). Present on both summary and detail
    /// responses, so it's usually populated as soon as a Movie is cached.
    var overview: String = ""
    /// Top-billed cast names, by TMDb credit order. Only the `/movie/{id}`
    /// detail endpoint (with `credits` appended) returns cast, so this is
    /// often empty until `MovieDetailView` lazily fetches full details —
    /// same inline-default reasoning as `voteAverage` re: migration.
    var cast: [String] = []

    init(
        tmdbID: Int,
        title: String,
        year: Int,
        posterURL: URL? = nil,
        runtimeMinutes: Int? = nil,
        director: String? = nil,
        genres: [String] = [],
        voteAverage: Double = 0,
        overview: String = "",
        cast: [String] = []
    ) {
        self.tmdbID = tmdbID
        self.title = title
        self.year = year
        self.posterURL = posterURL
        self.runtimeMinutes = runtimeMinutes
        self.director = director
        self.genres = genres
        self.voteAverage = voteAverage
        self.overview = overview
        self.cast = cast
    }
}
