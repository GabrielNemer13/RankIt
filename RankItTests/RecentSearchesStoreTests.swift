import XCTest
@testable import RankIt

final class RecentSearchesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "RecentSearchesStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func test_record_addsToFront() {
        let store = RecentSearchesStore(defaults: defaults)
        store.record("inception")
        store.record("dark knight")

        XCTAssertEqual(store.queries, ["dark knight", "inception"])
    }

    func test_record_isCaseInsensitiveDedup_andMovesToFront() {
        let store = RecentSearchesStore(defaults: defaults)
        store.record("Inception")
        store.record("dark knight")
        store.record("inception")

        XCTAssertEqual(store.queries, ["inception", "dark knight"], "re-recording an existing query (any case) should move it to the front without duplicating")
    }

    func test_record_capsAtTen() {
        let store = RecentSearchesStore(defaults: defaults)
        for i in 1...12 {
            store.record("query\(i)")
        }

        XCTAssertEqual(store.queries.count, 10)
        XCTAssertEqual(store.queries.first, "query12")
        XCTAssertFalse(store.queries.contains("query1"), "the oldest entries should fall off once past the limit")
    }

    func test_record_ignoresBlankQueries() {
        let store = RecentSearchesStore(defaults: defaults)
        store.record("   ")
        store.record("")

        XCTAssertTrue(store.queries.isEmpty)
    }

    func test_clear_removesEverything() {
        let store = RecentSearchesStore(defaults: defaults)
        store.record("inception")
        store.clear()

        XCTAssertTrue(store.queries.isEmpty)
    }
}
