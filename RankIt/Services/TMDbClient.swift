import Foundation

enum TMDbError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case requestFailed(Error)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No TMDb API key configured. Add one to Secrets.xcconfig."
        case .invalidURL:
            return "Couldn't build a valid TMDb request URL."
        case .invalidResponse:
            return "TMDb returned an unexpected response."
        case .requestFailed(let error):
            return "Network request failed: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Couldn't parse TMDb's response: \(error.localizedDescription)"
        }
    }
}

/// Everything the app needs from TMDb, expressed as a protocol so views/view
/// models can be driven by a fake in previews and tests without hitting the
/// network or requiring a real API key.
protocol MovieCatalogServicing {
    func searchMovies(query: String) async throws -> [Movie]
    func movieDetails(id: Int) async throws -> Movie
    func trending() async throws -> [Movie]
    func officialTrailers(movieID: Int) async throws -> [Trailer]
}

/// Talks to TMDb's v3 REST API. All movie metadata, search, trending, and
/// trailer video keys come from here — see SPEC.md's legal constraints:
/// this never fetches or hosts actual video/audio, only official YouTube
/// reference keys via the `videos` endpoint.
actor TMDbClient: MovieCatalogServicing {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func searchMovies(query: String) async throws -> [Movie] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response: TMDbPagedResponse<TMDbMovieSummaryDTO> = try await get(
            path: "search/movie",
            queryItems: [URLQueryItem(name: "query", value: trimmed)]
        )
        return response.results.map { $0.toMovie() }
    }

    func movieDetails(id: Int) async throws -> Movie {
        let dto: TMDbMovieDetailDTO = try await get(
            path: "movie/\(id)",
            queryItems: [URLQueryItem(name: "append_to_response", value: "credits")]
        )
        return dto.toMovie()
    }

    func trending() async throws -> [Movie] {
        let response: TMDbPagedResponse<TMDbMovieSummaryDTO> = try await get(
            path: "trending/movie/week"
        )
        return response.results.map { $0.toMovie() }
    }

    func officialTrailers(movieID: Int) async throws -> [Trailer] {
        let response: TMDbVideosResponseDTO = try await get(
            path: "movie/\(movieID)/videos"
        )
        return response.results.compactMap { $0.toTrailer(movieID: movieID) }
    }

    private func get<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        guard let apiKey = TMDbConfig.apiKey else {
            throw TMDbError.missingAPIKey
        }
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
            throw TMDbError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TMDbError.invalidResponse
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw TMDbError.decodingFailed(error)
        }
    }
}
