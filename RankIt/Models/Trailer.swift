import Foundation
import SwiftData

enum TrailerType: String, Codable, CaseIterable {
    case trailer
    case teaser
}

/// Cached reference only — never hosted video. Playback embeds the official
/// YouTube upload directly via `youtubeKey`. Only ever surface entries where
/// `official` is true.
@Model
final class Trailer {
    // No `.unique` -- CloudKit sync (planned) forbids it. Not currently
    // inserted anywhere (Discover only holds Trailer in-memory); fixed here
    // for forward-compat alongside the other 8 models.
    var id: UUID = UUID()
    var movieID: Int = 0
    var youtubeKey: String = ""
    var type: TrailerType = TrailerType.trailer
    var official: Bool = false

    init(
        id: UUID = UUID(),
        movieID: Int,
        youtubeKey: String,
        type: TrailerType,
        official: Bool
    ) {
        self.id = id
        self.movieID = movieID
        self.youtubeKey = youtubeKey
        self.type = type
        self.official = official
    }
}
