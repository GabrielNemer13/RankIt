import XCTest
@testable import RankIt

/// Serves a fixed, ordered queue of (status, data) responses regardless of
/// the requested URL -- sufficient here since each test only cares about
/// the sequence of responses `TMDbClient` receives, not per-endpoint
/// routing (real endpoint routing is exercised via the DTOs/mapping tests
/// instead).
final class URLProtocolStub: URLProtocol {
    struct StubResponse {
        let statusCode: Int
        let data: Data
    }

    static var responses: [StubResponse] = []
    static var requestedURLs: [URL] = []

    static func reset() {
        responses = []
        requestedURLs = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url { Self.requestedURLs.append(url) }
        guard !Self.responses.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let stub = Self.responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class TMDbClientTests: XCTestCase {
    private var session: URLSession!

    override func setUpWithError() throws {
        URLProtocolStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        session = URLSession(configuration: configuration)
        // Prevents `get()`'s `/configuration` fetch from consuming a slot
        // in `URLProtocolStub.responses` -- see its `markLoadedForTesting` doc.
        TMDbImageConfig.shared.markLoadedForTesting()
    }

    override func tearDownWithError() throws {
        URLProtocolStub.reset()
        session = nil
    }

    private func makeClient(sleep: @escaping (UInt64) async throws -> Void = { _ in }) -> TMDbClient {
        TMDbClient(session: session, apiKeyProvider: { "test-key" }, sleep: sleep)
    }

    private func jsonData(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    private func moviesPageJSON(page: Int, totalPages: Int, ids: [Int]) -> Data {
        jsonData([
            "page": page,
            "total_pages": totalPages,
            "results": ids.map { ["id": $0, "title": "Movie \($0)"] }
        ])
    }

    // MARK: - Missing key

    func test_missingAPIKey_throwsWithoutMakingARequest() async {
        let client = TMDbClient(session: session, apiKeyProvider: { nil })

        do {
            _ = try await client.trending(page: 1)
            XCTFail("expected missingAPIKey to be thrown")
        } catch let error as TMDbError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
        XCTAssertTrue(URLProtocolStub.requestedURLs.isEmpty, "should never hit the network without a key")
    }

    // MARK: - 401

    func test_unauthorized_throwsUnauthorizedError() async {
        URLProtocolStub.responses = [.init(statusCode: 401, data: Data())]
        let client = makeClient()

        do {
            _ = try await client.trending(page: 1)
            XCTFail("expected unauthorized to be thrown")
        } catch let error as TMDbError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    // MARK: - 429 retry with backoff

    func test_rateLimited_retriesAndSucceedsAfterTransientFailures() async {
        URLProtocolStub.responses = [
            .init(statusCode: 429, data: Data()),
            .init(statusCode: 429, data: Data()),
            .init(statusCode: 200, data: moviesPageJSON(page: 1, totalPages: 1, ids: [42]))
        ]
        var sleptDurations: [UInt64] = []
        let client = makeClient(sleep: { duration in sleptDurations.append(duration) })

        let page = try? await client.trending(page: 1)

        XCTAssertEqual(page?.movies.map(\.tmdbID), [42], "should succeed once the retries exhaust the transient 429s")
        XCTAssertEqual(sleptDurations.count, 2, "should back off exactly once per retried 429")
        // Exponential: 1s then 2s, expressed in nanoseconds.
        XCTAssertEqual(sleptDurations, [1_000_000_000, 2_000_000_000])
    }

    func test_rateLimited_exhaustsRetries_throwsRateLimitedError() async {
        URLProtocolStub.responses = [
            .init(statusCode: 429, data: Data()),
            .init(statusCode: 429, data: Data()),
            .init(statusCode: 429, data: Data())
        ]
        let client = makeClient()

        do {
            _ = try await client.trending(page: 1)
            XCTFail("expected rateLimited to be thrown once retries are exhausted")
        } catch let error as TMDbError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    // MARK: - Pagination

    func test_trending_decodesPageAndTotalPages() async {
        URLProtocolStub.responses = [.init(statusCode: 200, data: moviesPageJSON(page: 2, totalPages: 5, ids: [1, 2, 3]))]
        let client = makeClient()

        let page = try? await client.trending(page: 2)

        XCTAssertEqual(page?.page, 2)
        XCTAssertEqual(page?.totalPages, 5)
        XCTAssertTrue(page?.hasMorePages ?? false)
        XCTAssertEqual(page?.movies.map(\.tmdbID), [1, 2, 3])
    }

    func test_trending_lastPage_hasMorePagesIsFalse() async {
        URLProtocolStub.responses = [.init(statusCode: 200, data: moviesPageJSON(page: 5, totalPages: 5, ids: [1]))]
        let client = makeClient()

        let page = try? await client.trending(page: 5)

        XCTAssertFalse(page?.hasMorePages ?? true)
    }

    func test_searchMovies_emptyQuery_returnsEmptyPageWithoutRequest() async {
        let client = makeClient()

        let page = try? await client.searchMovies(query: "   ", page: 1)

        XCTAssertEqual(page, .empty)
        XCTAssertTrue(URLProtocolStub.requestedURLs.isEmpty)
    }

    func test_searchMovies_includesPageQueryParameter() async {
        URLProtocolStub.responses = [.init(statusCode: 200, data: moviesPageJSON(page: 3, totalPages: 3, ids: [7]))]
        let client = makeClient()

        _ = try? await client.searchMovies(query: "dune", page: 3)

        XCTAssertTrue(URLProtocolStub.requestedURLs.first?.query?.contains("page=3") ?? false)
    }

    // MARK: - Decoding failure

    func test_malformedResponse_throwsDecodingFailed() async {
        URLProtocolStub.responses = [.init(statusCode: 200, data: Data("not json".utf8))]
        let client = makeClient()

        do {
            _ = try await client.trending(page: 1)
            XCTFail("expected decodingFailed to be thrown")
        } catch let error as TMDbError {
            if case .decodingFailed = error {
                // expected
            } else {
                XCTFail("wrong TMDbError case: \(error)")
            }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
