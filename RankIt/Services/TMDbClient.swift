import Foundation

enum TMDbError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case requestFailed(String)
    case decodingFailed(String)

    /// `Error`/`Error` aren't `Equatable`, so associated errors are captured
    /// as their description -- only used to let tests compare cases without
    /// needing a bespoke `Equatable` conformance on every wrapped error type.
    init(requestFailed error: Error) { self = .requestFailed(String(describing: error)) }
    init(decodingFailed error: Error) { self = .decodingFailed(String(describing: error)) }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No TMDb API key configured. Add one to Secrets.xcconfig."
        case .invalidURL:
            return "Couldn't build a valid TMDb request URL."
        case .invalidResponse:
            return "TMDb returned an unexpected response."
        case .unauthorized:
            return "TMDb rejected the configured API key. Double-check Secrets.xcconfig."
        case .rateLimited:
            return "TMDb is rate-limiting requests right now. Try again in a moment."
        case .requestFailed(let description):
            return "Network request failed: \(description)"
        case .decodingFailed(let description):
            return "Couldn't parse TMDb's response: \(description)"
        }
    }
}

/// One page of a TMDb paginated list endpoint, plus enough to know whether
/// there's more to load.
struct MoviePage: Equatable {
    let movies: [Movie]
    let page: Int
    let totalPages: Int

    var hasMorePages: Bool { page < totalPages }

    static let empty = MoviePage(movies: [], page: 1, totalPages: 1)
}

/// Everything the app needs from TMDb, expressed as a protocol so views/view
/// models can be driven by a fake in previews and tests without hitting the
/// network or requiring a real API key.
protocol MovieCatalogServicing {
    func searchMovies(query: String, page: Int) async throws -> MoviePage
    func movieDetails(id: Int) async throws -> Movie
    func trending(page: Int) async throws -> MoviePage
    func officialTrailers(movieID: Int) async throws -> [Trailer]
}

/// Talks to TMDb's v3 REST API. All movie metadata, search, trending, and
/// trailer video keys come from here — see SPEC.md's legal constraints:
/// this never fetches or hosts actual video/audio, only official YouTube
/// reference keys via the `videos` endpoint.
actor TMDbClient: MovieCatalogServicing {
    private let session: URLSession
    private let decoder: JSONDecoder
    /// Injectable so tests can exercise the 429 retry path without actually
    /// waiting out the backoff delay.
    private let sleep: (UInt64) async throws -> Void
    /// Defaults to reading `TMDbConfig.apiKey` (from Info.plist, see its
    /// doc comment); injectable because the test bundle's own Info.plist
    /// never has a real key, so tests need to supply one to exercise
    /// anything past `.missingAPIKey`.
    private let apiKeyProvider: () -> String?

    init(
        session: URLSession = .shared,
        apiKeyProvider: @escaping () -> String? = { TMDbConfig.apiKey },
        sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.session = session
        self.decoder = JSONDecoder()
        self.apiKeyProvider = apiKeyProvider
        self.sleep = sleep
    }

    func searchMovies(query: String, page: Int = 1) async throws -> MoviePage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        let response: TMDbPagedResponse<TMDbMovieSummaryDTO> = try await get(
            path: "search/movie",
            queryItems: [
                URLQueryItem(name: "query", value: trimmed),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
        return MoviePage(movies: response.results.map { $0.toMovie() }, page: response.page, totalPages: response.totalPages)
    }

    func movieDetails(id: Int) async throws -> Movie {
        let dto: TMDbMovieDetailDTO = try await get(
            path: "movie/\(id)",
            queryItems: [URLQueryItem(name: "append_to_response", value: "credits")]
        )
        return dto.toMovie()
    }

    func trending(page: Int = 1) async throws -> MoviePage {
        let response: TMDbPagedResponse<TMDbMovieSummaryDTO> = try await get(
            path: "trending/movie/week",
            queryItems: [URLQueryItem(name: "page", value: String(page))]
        )
        return MoviePage(movies: response.results.map { $0.toMovie() }, page: response.page, totalPages: response.totalPages)
    }

    func officialTrailers(movieID: Int) async throws -> [Trailer] {
        let response: TMDbVideosResponseDTO = try await get(
            path: "movie/\(movieID)/videos"
        )
        return response.results.compactMap { $0.toTrailer(movieID: movieID) }
    }

    /// Exponential backoff for a 429 retry: 1s, 2s, 4s.
    static func backoffDelay(attempt: Int) -> TimeInterval {
        pow(2.0, Double(attempt))
    }

    private static let maxRetries = 2

    private func get<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        retriesRemaining: Int = TMDbClient.maxRetries
    ) async throws -> Response {
        guard let apiKey = apiKeyProvider() else {
            throw TMDbError.missingAPIKey
        }
        await TMDbImageConfig.shared.load(apiKey: apiKey, baseAPIURL: TMDbConfig.baseURL, session: session)

        guard var components = URLComponents(
            url: TMDbConfig.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw TMDbError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)] + queryItems
        guard let url = components.url else {
            throw TMDbError.invalidURL
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw TMDbError(requestFailed: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDbError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401:
            throw TMDbError.unauthorized
        case 429:
            guard retriesRemaining > 0 else { throw TMDbError.rateLimited }
            let attempt = TMDbClient.maxRetries - retriesRemaining
            try await sleep(UInt64(TMDbClient.backoffDelay(attempt: attempt) * 1_000_000_000))
            return try await get(path: path, queryItems: queryItems, retriesRemaining: retriesRemaining - 1)
        default:
            throw TMDbError.invalidResponse
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw TMDbError(decodingFailed: error)
        }
    }
}
