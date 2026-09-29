import Foundation

// MARK: - Wire DTOs (raw TMDb JSON shapes)

struct TMDbPagedResponse<Result: Decodable>: Decodable {
    let page: Int
    let totalPages: Int
    let results: [Result]

    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
    }
}

/// `/configuration`'s `images` block — base URLs and the size buckets
/// available for each image type. Only poster sizes are used today.
struct TMDbConfigurationDTO: Decodable {
    struct Images: Decodable {
        let secureBaseURL: String
        let posterSizes: [String]

        enum CodingKeys: String, CodingKey {
            case secureBaseURL = "secure_base_url"
            case posterSizes = "poster_sizes"
        }
    }

    let images: Images
}

struct TMDbMovieSummaryDTO: Decodable {
    let id: Int
    let title: String
    let releaseDate: String?
    let posterPath: String?
    let genreIDs: [Int]?
    let voteAverage: Double?
    let overview: String?

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case genreIDs = "genre_ids"
        case voteAverage = "vote_average"
    }
}

struct TMDbGenreDTO: Decodable {
    let id: Int
    let name: String
}

struct TMDbCrewMemberDTO: Decodable {
    let job: String
    let name: String
}

struct TMDbCastMemberDTO: Decodable {
    let name: String
    let order: Int?
}

struct TMDbCreditsDTO: Decodable {
    let cast: [TMDbCastMemberDTO]
    let crew: [TMDbCrewMemberDTO]
}

struct TMDbMovieDetailDTO: Decodable {
    let id: Int
    let title: String
    let releaseDate: String?
    let posterPath: String?
    let runtime: Int?
    let genres: [TMDbGenreDTO]
    let credits: TMDbCreditsDTO?
    let voteAverage: Double?
    let overview: String?

    enum CodingKeys: String, CodingKey {
        case id, title, runtime, genres, credits, overview
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
    }
}

struct TMDbVideoDTO: Decodable {
    let key: String
    let site: String
    let type: String
    let official: Bool
}

struct TMDbVideosResponseDTO: Decodable {
    let results: [TMDbVideoDTO]
}

// MARK: - Mapping to app models

/// TMDb's movie genre ID list is a small, stable, publicly documented
/// taxonomy — hardcoded here rather than fetched, since `/search/movie` and
/// `/trending` only return genre IDs, not names.
enum TMDbGenreCatalog {
    private static let names: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy",
        80: "Crime", 99: "Documentary", 18: "Drama", 10751: "Family",
        14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music",
        9648: "Mystery", 10749: "Romance", 878: "Science Fiction",
        10770: "TV Movie", 53: "Thriller", 10752: "War", 37: "Western"
    ]

    static func name(for id: Int) -> String? { names[id] }
}

enum TMDbMapping {
    static func year(from releaseDate: String?) -> Int {
        guard let releaseDate, releaseDate.count >= 4 else { return 0 }
        return Int(releaseDate.prefix(4)) ?? 0
    }

    /// Uses whatever base URL/poster size `TMDbImageConfig` currently has
    /// cached — the hardcoded default before the first successful
    /// `/configuration` fetch, or the live values after.
    static func posterURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return TMDbImageConfig.shared.posterURL(forPath: path)
    }
}

extension TMDbMovieSummaryDTO {
    func toMovie() -> Movie {
        Movie(
            tmdbID: id,
            title: title,
            year: TMDbMapping.year(from: releaseDate),
            posterURL: TMDbMapping.posterURL(posterPath),
            genres: (genreIDs ?? []).compactMap(TMDbGenreCatalog.name(for:)),
            voteAverage: voteAverage ?? 0,
            overview: overview ?? ""
        )
    }
}

extension TMDbMovieDetailDTO {
    func toMovie() -> Movie {
        Movie(
            tmdbID: id,
            title: title,
            year: TMDbMapping.year(from: releaseDate),
            posterURL: TMDbMapping.posterURL(posterPath),
            runtimeMinutes: runtime,
            director: credits?.crew.first(where: { $0.job == "Director" })?.name,
            genres: genres.map(\.name),
            voteAverage: voteAverage ?? 0,
            overview: overview ?? "",
            cast: (credits?.cast ?? [])
                .sorted { ($0.order ?? .max) < ($1.order ?? .max) }
                .prefix(10)
                .map(\.name)
        )
    }
}

extension TMDbVideoDTO {
    /// `nil` if this video isn't a YouTube-hosted official Trailer/Teaser —
    /// per SPEC.md, only those should ever be surfaced.
    func toTrailer(movieID: Int) -> Trailer? {
        guard official, site == "YouTube" else { return nil }
        let trailerType: TrailerType
        switch type {
        case "Trailer": trailerType = .trailer
        case "Teaser": trailerType = .teaser
        default: return nil
        }
        return Trailer(movieID: movieID, youtubeKey: key, type: trailerType, official: official)
    }
}
