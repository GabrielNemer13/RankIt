import XCTest
import SwiftData
@testable import RankIt

/// Confirms `LogFlowViewModel.resolvedRankPosition` -- the conversion from
/// `RankingEngine`'s array-index-based `insertionIndex`/`Completion` into a
/// stored `rankPosition` value -- stays correct once a tier already has
/// gaps in its `rankPosition` sequence (e.g. [0, 1, 3]), which happens
/// whenever a movie is deleted or moved to a different tier (see
/// `MovieDetailView`'s gap-tolerant deletion/tier-change convention).
///
/// Trace result: the conversion already works on rankPosition *values*, not
/// array indices. `RankingEngine` itself only ever produces an index into
/// its own `items` array (display order); `resolvedRankPosition` reads
/// `engine.items[arrayIndex].loggedMovie.rankPosition` to find the
/// *threshold value* at that display position, then shifts every row whose
/// rankPosition *value* is >= that threshold -- never comparing or
/// iterating by array index. So a gap elsewhere in the tier can never be
/// mistaken for a valid slot or corrupt the shift: these tests lock that in
/// rather than fixing anything, since nothing here was found broken. No
/// re-densifying pass was added for the same reason -- it would be extra
/// complexity with no correctness gain, since gaps are already provably
/// harmless to this logic.
@MainActor
final class GapTolerantInsertionTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var currentUser: User!

    override func setUpWithError() throws {
        let schema = Schema([
            User.self, Movie.self, LoggedMovie.self, ComparisonEvent.self,
            Watchlist.self, Follow.self, ActivityFeedItem.self, Trailer.self,
            DiscoverInteraction.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(modelContainer)
        currentUser = User(username: "test", displayName: "Test")
        modelContext.insert(currentUser)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
        currentUser = nil
    }

    // MARK: - Helpers

    private enum Choice {
        case newWins
        case existingWins
        case tie
    }

    /// Seeds a tier directly with specific (possibly gapped) `rankPosition`
    /// values, one `LoggedMovie` per value, already in display order.
    @discardableResult
    private func seedGappedTier(_ tier: MovieTier, tmdbIDs: [Int], rankPositions: [Int]) -> [LoggedMovie] {
        zip(tmdbIDs, rankPositions).map { tmdbID, rank in
            let movie = Movie(tmdbID: tmdbID, title: "Movie \(tmdbID)", year: 2000)
            modelContext.insert(movie)
            let logged = LoggedMovie(userID: currentUser.id, movieID: tmdbID, tier: tier, rankPosition: rank)
            modelContext.insert(logged)
            return logged
        }
    }

    @discardableResult
    private func insertNewMovie(tmdbID: Int, tier: MovieTier, choices: [Choice]) -> LoggedMovie {
        let movie = Movie(tmdbID: tmdbID, title: "New \(tmdbID)", year: 2000)
        modelContext.insert(movie)
        let viewModel = LogFlowViewModel(movie: movie, tier: tier, currentUser: currentUser, modelContext: modelContext)
        for choice in choices {
            switch choice {
            case .newWins: viewModel.chooseNew()
            case .existingWins: viewModel.chooseExisting()
            case .tie: viewModel.chooseTie()
            }
        }
        guard let saved = viewModel.save() else {
            XCTFail("save() returned nil -- engine wasn't complete after the given choices")
            return LoggedMovie(userID: currentUser.id, movieID: tmdbID, tier: tier, rankPosition: -999)
        }
        return saved
    }

    private func fetchTier(_ tier: MovieTier) -> [LoggedMovie] {
        let userID = currentUser.id
        let descriptor = FetchDescriptor<LoggedMovie>(predicate: #Predicate<LoggedMovie> { $0.userID == userID })
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { $0.tier == tier }.sorted(by: LoggedMovie.isOrderedForDisplay)
    }

    private func assertAllRankPositionsUnique(_ tier: MovieTier, file: StaticString = #filePath, line: UInt = #line) {
        let ranks = fetchTier(tier).map(\.rankPosition)
        XCTAssertEqual(ranks.count, Set(ranks).count, "expected every rankPosition in \(tier) to be unique, got \(ranks)", file: file, line: line)
    }

    // MARK: - Tier [0, 1, 3]: one no-gap boundary (0→1), one gapped boundary (1→3)

    func test_insertAtTop_intoGappedTier() {
        seedGappedTier(.loved, tmdbIDs: [1, 2, 3], rankPositions: [0, 1, 3])

        let newLog = insertNewMovie(tmdbID: 4, tier: .loved, choices: [.newWins, .newWins])

        let tier = fetchTier(.loved)
        XCTAssertEqual(tier.map(\.movieID), [4, 1, 2, 3], "new movie should land at the very top")
        XCTAssertEqual(newLog.rankPosition, 0)
        assertAllRankPositionsUnique(.loved)
    }

    func test_insertInMiddle_betweenValuesWithoutGap() {
        seedGappedTier(.loved, tmdbIDs: [1, 2, 3], rankPositions: [0, 1, 3])

        // Lands between rankPosition 0 and rankPosition 1 -- a boundary with no gap.
        let newLog = insertNewMovie(tmdbID: 4, tier: .loved, choices: [.newWins, .existingWins])

        let tier = fetchTier(.loved)
        XCTAssertEqual(tier.map(\.movieID), [1, 4, 2, 3], "new movie should land between the first and second movies")
        XCTAssertEqual(newLog.rankPosition, 1)
        assertAllRankPositionsUnique(.loved)
    }

    func test_insertInMiddle_betweenValuesWithGap() {
        seedGappedTier(.loved, tmdbIDs: [1, 2, 3], rankPositions: [0, 1, 3])

        // Lands between rankPosition 1 and rankPosition 3 -- a boundary that
        // already has a gap (value 2 is missing).
        let newLog = insertNewMovie(tmdbID: 4, tier: .loved, choices: [.existingWins, .newWins])

        let tier = fetchTier(.loved)
        XCTAssertEqual(tier.map(\.movieID), [1, 2, 4, 3], "new movie should land between the second and third movies")
        XCTAssertEqual(newLog.rankPosition, 3, "should take the boundary's existing rankPosition value, not try to reuse the gap")
        assertAllRankPositionsUnique(.loved)
    }

    // MARK: - Tier [0, 2, 5]: every boundary already has a gap

    func test_insertAtBottom_intoGappedTier() {
        seedGappedTier(.liked, tmdbIDs: [10, 11, 12], rankPositions: [0, 2, 5])

        let newLog = insertNewMovie(tmdbID: 13, tier: .liked, choices: [.existingWins, .existingWins])

        let tier = fetchTier(.liked)
        XCTAssertEqual(tier.map(\.movieID), [10, 11, 12, 13], "new movie should land at the very bottom")
        XCTAssertEqual(newLog.rankPosition, 6, "should append right after the last existing rankPosition value")
        assertAllRankPositionsUnique(.liked)
    }

    func test_insertInMiddle_ofFullyGappedTier() {
        seedGappedTier(.liked, tmdbIDs: [10, 11, 12], rankPositions: [0, 2, 5])

        // Lands between rankPosition 2 and rankPosition 5.
        let newLog = insertNewMovie(tmdbID: 13, tier: .liked, choices: [.existingWins, .newWins])

        let tier = fetchTier(.liked)
        XCTAssertEqual(tier.map(\.movieID), [10, 11, 13, 12])
        XCTAssertEqual(newLog.rankPosition, 5)
        assertAllRankPositionsUnique(.liked)
    }

    // MARK: - Ties

    func test_tieWithItemJustAfterGap() {
        let seeded = seedGappedTier(.loved, tmdbIDs: [1, 2, 3], rankPositions: [0, 1, 3])
        let tiedPartner = seeded[2] // movieID 3, rankPosition 3, sits right after the 1→3 gap

        let newLog = insertNewMovie(tmdbID: 4, tier: .loved, choices: [.existingWins, .tie])

        XCTAssertEqual(newLog.rankPosition, tiedPartner.rankPosition, "tying should reuse the partner's exact rankPosition value")

        let tier = fetchTier(.loved)
        XCTAssertEqual(tier.map(\.rankPosition), [0, 1, 3, 3], "only the tied pair should share a rankPosition; everything else stays distinct")
        XCTAssertEqual(Set(tier.suffix(2).map(\.movieID)), Set([3, 4]), "the tied pair should be the last two movies in display order")
    }
}
