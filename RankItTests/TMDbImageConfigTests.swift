import XCTest
@testable import RankIt

final class TMDbImageConfigTests: XCTestCase {
    private var session: URLSession!

    override func setUpWithError() throws {
        URLProtocolStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        session = URLSession(configuration: configuration)
        TMDbImageConfig.shared.resetForTesting()
    }

    override func tearDownWithError() throws {
        URLProtocolStub.reset()
        TMDbImageConfig.shared.resetForTesting()
        session = nil
    }

    func test_defaultPosterURL_beforeAnyLoad_usesHardcodedFallback() {
        let url = TMDbImageConfig.shared.posterURL(forPath: "/abc.jpg")
        XCTAssertEqual(url.absoluteString, "https://image.tmdb.org/t/p/w500/abc.jpg")
    }

    func test_successfulLoad_updatesBaseURLAndPreferredPosterSize() async {
        let json = try! JSONSerialization.data(withJSONObject: [
            "images": [
                "secure_base_url": "https://images.example.com/t/p/",
                "poster_sizes": ["w92", "w154", "w185", "w342", "w500", "w780", "original"]
            ]
        ])
        URLProtocolStub.responses = [.init(statusCode: 200, data: json)]

        await TMDbImageConfig.shared.load(apiKey: "key", baseAPIURL: URL(string: "https://api.example.com/3")!, session: session)

        let url = TMDbImageConfig.shared.posterURL(forPath: "/abc.jpg")
        XCTAssertEqual(url.absoluteString, "https://images.example.com/t/p/w500/abc.jpg", "should prefer w500 when TMDb still offers it")
    }

    func test_successfulLoad_withoutW500_fallsBackToLargestWSize() async {
        let json = try! JSONSerialization.data(withJSONObject: [
            "images": [
                "secure_base_url": "https://images.example.com/t/p/",
                "poster_sizes": ["w92", "w154", "original"]
            ]
        ])
        URLProtocolStub.responses = [.init(statusCode: 200, data: json)]

        await TMDbImageConfig.shared.load(apiKey: "key", baseAPIURL: URL(string: "https://api.example.com/3")!, session: session)

        let url = TMDbImageConfig.shared.posterURL(forPath: "/abc.jpg")
        XCTAssertEqual(url.absoluteString, "https://images.example.com/t/p/w154/abc.jpg")
    }

    func test_failedLoad_keepsDefaultValues() async {
        URLProtocolStub.responses = [.init(statusCode: 500, data: Data())]

        await TMDbImageConfig.shared.load(apiKey: "key", baseAPIURL: URL(string: "https://api.example.com/3")!, session: session)

        let url = TMDbImageConfig.shared.posterURL(forPath: "/abc.jpg")
        XCTAssertEqual(url.absoluteString, "https://image.tmdb.org/t/p/w500/abc.jpg")
    }

    func test_load_onlyEverAttemptsOnce() async {
        let json = try! JSONSerialization.data(withJSONObject: [
            "images": ["secure_base_url": "https://images.example.com/t/p/", "poster_sizes": ["w500"]]
        ])
        URLProtocolStub.responses = [.init(statusCode: 200, data: json)]

        await TMDbImageConfig.shared.load(apiKey: "key", baseAPIURL: URL(string: "https://api.example.com/3")!, session: session)
        // Second call: no more stubbed responses queued -- if `load` tried
        // again it would hit the "no responses left" failure branch and
        // (if it applied results) revert state; asserting the first load's
        // result still holds proves the second call was a no-op.
        await TMDbImageConfig.shared.load(apiKey: "key", baseAPIURL: URL(string: "https://api.example.com/3")!, session: session)

        let url = TMDbImageConfig.shared.posterURL(forPath: "/abc.jpg")
        XCTAssertEqual(url.absoluteString, "https://images.example.com/t/p/w500/abc.jpg")
        XCTAssertEqual(URLProtocolStub.requestedURLs.count, 1, "load() must only ever issue one request per process")
    }
}
