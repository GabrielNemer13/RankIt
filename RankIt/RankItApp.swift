import SwiftUI
import SwiftData

@main
struct RankItApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, migrationPlan: RankItMigrationPlan.self, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    /// Falls back to a small offline sample catalog when no TMDb key is
    /// configured yet, so the Log flow is still usable out of the box.
    /// Once `Secrets.xcconfig` has a real key this automatically switches
    /// to live TMDb results.
    private var catalogService: any MovieCatalogServicing {
        TMDbConfig.apiKey != nil ? TMDbClient() : PreviewMovieCatalogService()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.movieCatalogService, catalogService)
        }
        .modelContainer(modelContainer)
    }
}
