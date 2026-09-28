import Foundation

/// Reads the TMDb API key out of Info.plist, where it lands via the
/// `TMDB_API_KEY` build setting in the gitignored `Secrets.xcconfig`
/// (see `Secrets.xcconfig.example` for setup). Never hardcode the key here.
enum TMDbConfig {
    static var apiKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String,
              !key.isEmpty else {
            return nil
        }
        return key
    }

    static let baseURL = URL(string: "https://api.themoviedb.org/3")!
    static let imageBaseURL = URL(string: "https://image.tmdb.org/t/p/w500")!
}
