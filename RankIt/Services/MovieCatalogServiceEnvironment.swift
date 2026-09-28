import SwiftUI

private struct MovieCatalogServiceKey: EnvironmentKey {
    static let defaultValue: any MovieCatalogServicing = TMDbClient()
}

extension EnvironmentValues {
    var movieCatalogService: any MovieCatalogServicing {
        get { self[MovieCatalogServiceKey.self] }
        set { self[MovieCatalogServiceKey.self] = newValue }
    }
}
