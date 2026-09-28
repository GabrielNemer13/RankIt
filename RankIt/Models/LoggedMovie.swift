import Foundation
import SwiftData

enum MovieTier: String, Codable, CaseIterable {
    case loved
    case liked
    case disliked
}

extension MovieTier {
    /// Shared display glyph — used anywhere a tier needs a compact visual
    /// (Library section headers, tier pickers, the Search "already logged" badge).
    var emoji: String {
        switch self {
        case .loved: return "🟢"
        case .liked: return "🟡"
        case .disliked: return "🔴"
        }
    }
}

/// Core object — one per user per watch. `rankPosition` is maintained
/// exclusively by `RankingEngine` and is unique per user+tier *except* when
/// two movies were tied against each other — in that case they intentionally
/// share a `rankPosition`, and `watchedDate` (more recent first) breaks the
/// tie for display. Always sort tier lists with `LoggedMovie.displayOrder`
/// or `LoggedMovie.queryOrder` rather than `rankPosition` alone.
@Model
final class LoggedMovie {
    // No `.unique` -- CloudKit sync (planned) forbids it. Not a dedup
    // mechanism here anyway: multiple LoggedMovie rows for the same
    // user+movie are valid by design (rewatches).
    var id: UUID = UUID()
    var userID: UUID = UUID()
    var movieID: Int = 0
    var watchedDate: Date = Date.now
    var tier: MovieTier = MovieTier.loved
    var rankPosition: Int = 0
    var isRewatch: Bool = false
    var reviewText: String?
    var isLiked: Bool = false
    var containsSpoilers: Bool = false

    init(
        id: UUID = UUID(),
        userID: UUID,
        movieID: Int,
        watchedDate: Date = .now,
        tier: MovieTier,
        rankPosition: Int,
        isRewatch: Bool = false,
        reviewText: String? = nil,
        isLiked: Bool = false,
        containsSpoilers: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.movieID = movieID
        self.watchedDate = watchedDate
        self.tier = tier
        self.rankPosition = rankPosition
        self.isRewatch = isRewatch
        self.reviewText = reviewText
        self.isLiked = isLiked
        self.containsSpoilers = containsSpoilers
    }
}

extension LoggedMovie {
    /// Canonical per-tier display order: `rankPosition` ascending (best
    /// first), then `watchedDate` descending as the tiebreak for movies that
    /// share a `rankPosition` because they were tied against each other.
    static func isOrderedForDisplay(_ lhs: LoggedMovie, _ rhs: LoggedMovie) -> Bool {
        if lhs.rankPosition != rhs.rankPosition {
            return lhs.rankPosition < rhs.rankPosition
        }
        return lhs.watchedDate > rhs.watchedDate
    }

    /// Same ordering as `isOrderedForDisplay`, expressed as `SortDescriptor`s
    /// for use with SwiftData `@Query(sort:)` / `FetchDescriptor`.
    static var queryOrder: [SortDescriptor<LoggedMovie>] {
        [
            SortDescriptor(\LoggedMovie.rankPosition, order: .forward),
            SortDescriptor(\LoggedMovie.watchedDate, order: .reverse)
        ]
    }
}
