import SwiftData

/// The current (and, so far, only) schema version. Deliberately lists the
/// existing top-level `@Model` classes as-is rather than nesting a copy of
/// each inside this enum -- see docs/MIGRATIONS.md for why that's the
/// right call for now, and when it stops being enough.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            User.self,
            Movie.self,
            LoggedMovie.self,
            ComparisonEvent.self,
            Watchlist.self,
            Follow.self,
            ActivityFeedItem.self,
            Trailer.self,
            DiscoverInteraction.self
        ]
    }
}

/// Wired into `RankItApp`'s `ModelContainer` so SwiftData tracks a real
/// schema version in the store's metadata from now on, instead of nothing.
/// `stages` is empty because there's only one version -- see
/// docs/MIGRATIONS.md for what to add here when SchemaV2 shows up.
enum RankItMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
