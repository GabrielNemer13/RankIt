import Foundation

/// Caches TMDb's `/configuration` image base URL and poster size buckets,
/// so they're fetched once and reused rather than hardcoded forever. Reads
/// are synchronous (needed by `TMDbMapping.posterURL`, called from a
/// `Decodable` mapping context) and just return whatever is currently
/// cached — the hardcoded default until `load()` succeeds at least once,
/// then the live values from then on. A failed `load()` silently keeps
/// the existing (default or previously-loaded) values.
final class TMDbImageConfig {
    static let shared = TMDbImageConfig()

    private let lock = NSLock()
    private var baseURL = URL(string: "https://image.tmdb.org/t/p/")!
    private var posterSize = "w500"
    private var hasLoaded = false

    private init() {}

    func posterURL(forPath path: String) -> URL {
        lock.lock()
        let url = baseURL.appendingPathComponent(posterSize).appendingPathComponent(path)
        lock.unlock()
        return url
    }

    /// Fetches `/configuration` at most once per process; later calls are a
    /// no-op even if the first attempt failed, since `TMDbClient` retries
    /// this on every request it makes and a persistently-failing endpoint
    /// shouldn't cost a network round trip on every single call.
    func load(apiKey: String, baseAPIURL: URL, session: URLSession) async {
        lock.lock()
        let alreadyAttempted = hasLoaded
        hasLoaded = true
        lock.unlock()
        guard !alreadyAttempted else { return }

        guard var components = URLComponents(
            url: baseAPIURL.appendingPathComponent("configuration"),
            resolvingAgainstBaseURL: false
        ) else { return }
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        guard let url = components.url else { return }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else { return }
            let config = try JSONDecoder().decode(TMDbConfigurationDTO.self, from: data)
            guard let resolvedBaseURL = URL(string: config.images.secureBaseURL) else { return }
            // Prefer w500 (this app's existing default) when TMDb still
            // offers it; otherwise fall back to whatever size is closest
            // without exceeding it, or the largest available.
            let preferred = config.images.posterSizes.first { $0 == "w500" }
                ?? config.images.posterSizes.last { $0.hasPrefix("w") }
                ?? config.images.posterSizes.first

            lock.lock()
            baseURL = resolvedBaseURL
            if let preferred { posterSize = preferred }
            lock.unlock()
        } catch {
            // Keep existing cached values -- see doc comment.
        }
    }
}

#if DEBUG
extension TMDbImageConfig {
    /// Test-only: marks the config as already loaded so `TMDbClient`'s
    /// `get()` won't issue a `/configuration` request, which would
    /// otherwise consume a slot in a stubbed test session's response
    /// queue non-deterministically. Never called from production code.
    func markLoadedForTesting() {
        lock.lock()
        hasLoaded = true
        lock.unlock()
    }

    /// Test-only: restores default state, for tests that specifically
    /// exercise `load(...)` itself.
    func resetForTesting() {
        lock.lock()
        hasLoaded = false
        baseURL = URL(string: "https://image.tmdb.org/t/p/")!
        posterSize = "w500"
        lock.unlock()
    }
}
#endif
