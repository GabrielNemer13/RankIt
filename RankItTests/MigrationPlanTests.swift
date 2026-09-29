import XCTest
import SwiftData
@testable import RankIt

// MARK: - Throwaway test-only schema pair (Part 2 of this suite)
//
// Demonstrates the "usual" nested-type-per-version pattern that RankIt's
// *production* schema (`SchemaV1` in RankItSchema.swift) deliberately
// avoids for now -- see docs/MIGRATIONS.md. This pair only ever needs to
// exist here, in a throwaway test store, to prove the pattern itself
// works when a real additive change eventually needs it.

enum TestSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Widget.self] }

    @Model
    final class Widget {
        var name: String = ""
        init(name: String) {
            self.name = name
        }
    }
}

enum TestSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [Widget.self] }

    @Model
    final class Widget {
        var name: String = ""
        /// The throwaway additive field: optional, with an inline
        /// default -- exactly the lightweight-migration-safe shape
        /// docs/MIGRATIONS.md recommends.
        var note: String?
        init(name: String, note: String? = nil) {
            self.name = name
            self.note = note
        }
    }
}

enum TestMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TestSchemaV1.self, TestSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: TestSchemaV1.self, toVersion: TestSchemaV2.self)]
    }
}

final class MigrationPlanTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        storeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MigrationPlanTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
    }

    // MARK: - Part 1: reopening RankIt's real SchemaV1 through the plan

    private func makeRankItContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: storeDirectory.appendingPathComponent("RankIt.store"))
        return try ModelContainer(for: schema, migrationPlan: RankItMigrationPlan.self, configurations: [configuration])
    }

    /// Writes one of everything -- including a tied pair of `LoggedMovie`s,
    /// which share a `rankPosition` by design (see `LoggedMovie`'s doc
    /// comment) -- closes the container, reopens a fresh one against the
    /// same store through `RankItMigrationPlan`, and confirms every row
    /// (and the tie itself) survived.
    func test_reopeningAnExistingStoreThroughTheMigrationPlan_preservesAllData() throws {
        let userID = UUID()
        do {
            let container = try makeRankItContainer()
            let context = ModelContext(container)
            context.insert(User(id: userID, username: "me", displayName: "Me"))
            context.insert(Movie(tmdbID: 1, title: "A", year: 2000))
            context.insert(Movie(tmdbID: 2, title: "B", year: 2000))
            // Tied pair: same tier, same rankPosition.
            context.insert(LoggedMovie(userID: userID, movieID: 1, tier: .loved, rankPosition: 0))
            context.insert(LoggedMovie(userID: userID, movieID: 2, tier: .loved, rankPosition: 0))
            context.insert(ComparisonEvent(userID: userID, movieAID: 1, movieBID: 2, winnerID: nil, tier: .loved))
            context.insert(Watchlist(userID: userID, movieID: 2))
            try context.save()
        }

        // Reopening with a brand-new ModelContainer against the same store
        // URL simulates the next app launch.
        let reopened = try makeRankItContainer()
        let context = ModelContext(reopened)

        let users = try context.fetch(FetchDescriptor<User>())
        let loggedMovies = try context.fetch(FetchDescriptor<LoggedMovie>(predicate: #Predicate { $0.userID == userID }))
        let events = try context.fetch(FetchDescriptor<ComparisonEvent>())
        let watchlist = try context.fetch(FetchDescriptor<Watchlist>())

        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(loggedMovies.count, 2)
        XCTAssertEqual(Set(loggedMovies.map(\.rankPosition)), [0], "the tied rankPosition must survive intact")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.winnerID, nil, "the tie's nil winnerID must survive, not get coerced to something else")
        XCTAssertEqual(watchlist.count, 1)
    }

    // MARK: - Part 2: a genuine additive SchemaV2 migrates lightweight

    func test_additiveOptionalField_migratesLightweight_withoutDataLoss() throws {
        let storeURL = storeDirectory.appendingPathComponent("Widgets.store")

        do {
            let schema = Schema(versionedSchema: TestSchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(TestSchemaV1.Widget(name: "gadget"))
            context.insert(TestSchemaV1.Widget(name: "gizmo"))
            try context.save()
        }

        // Reopen at V2 through the migration plan -- the store on disk
        // still only has V1's columns; SwiftData must lightweight-migrate
        // it up to V2's shape (adding `note`, defaulted to nil) in place.
        let v2Schema = Schema(versionedSchema: TestSchemaV2.self)
        let v2Configuration = ModelConfiguration(schema: v2Schema, url: storeURL)
        let v2Container = try ModelContainer(for: v2Schema, migrationPlan: TestMigrationPlan.self, configurations: [v2Configuration])
        let v2Context = ModelContext(v2Container)

        let widgets = try v2Context.fetch(FetchDescriptor<TestSchemaV2.Widget>())

        XCTAssertEqual(widgets.count, 2, "no rows should be lost across the migration")
        XCTAssertEqual(Set(widgets.map(\.name)), ["gadget", "gizmo"])
        XCTAssertTrue(widgets.allSatisfy { $0.note == nil }, "the new field should default to nil rather than crash or get garbage data")
    }
}
