import Foundation
import SwiftData

/// One user's logged movies and watchlist, as a portable JSON snapshot.
/// `formatVersion` lets a future importer (out of scope for now -- see
/// docs/MIGRATIONS.md) tell old export files apart from newer ones without
/// guessing from the shape of the JSON.
struct LibraryExport: Codable {
    struct LoggedEntry: Codable {
        let title: String
        let tmdbID: Int
        let tier: String
        let displayRank: Int
        let score: Double
        let watchedDate: Date
    }

    struct WatchlistEntry: Codable {
        let title: String
        let tmdbID: Int
        let addedDate: Date
    }

    static let currentFormatVersion = 1

    let formatVersion: Int
    let exportedDate: Date
    let loggedMovies: [LoggedEntry]
    let watchlist: [WatchlistEntry]
}

enum LibraryExporter {
    private static let tierDisplayOrder: [MovieTier] = [.loved, .liked, .disliked]

    /// Builds the export in memory. `nil` titles (a `Movie` row that
    /// somehow isn't cached) fall back to "Unknown movie" rather than
    /// dropping the entry -- an export should never silently lose rows.
    static func build(userID: UUID, modelContext: ModelContext) -> LibraryExport {
        let loggedDescriptor = FetchDescriptor<LoggedMovie>(predicate: #Predicate<LoggedMovie> { $0.userID == userID })
        let loggedMovies = ((try? modelContext.fetch(loggedDescriptor)) ?? [])
        let watchlistDescriptor = FetchDescriptor<Watchlist>(predicate: #Predicate<Watchlist> { $0.userID == userID })
        let watchlistEntries = ((try? modelContext.fetch(watchlistDescriptor)) ?? [])
            .sorted { $0.addedDate > $1.addedDate }

        let allMoviesDescriptor = FetchDescriptor<Movie>()
        let moviesByTmdbID = Dictionary(
            uniqueKeysWithValues: ((try? modelContext.fetch(allMoviesDescriptor)) ?? []).map { ($0.tmdbID, $0) }
        )

        var loggedExportEntries: [LibraryExport.LoggedEntry] = []
        let byTier = Dictionary(grouping: loggedMovies, by: \.tier)
        for tier in tierDisplayOrder {
            guard let entries = byTier[tier], !entries.isEmpty else { continue }
            let sorted = entries.sorted(by: LoggedMovie.isOrderedForDisplay)
            let scores = RatingScore.scores(forDisplayOrderedTier: sorted)
            for (index, logged) in sorted.enumerated() {
                let title = moviesByTmdbID[logged.movieID]?.title ?? "Unknown movie"
                loggedExportEntries.append(LibraryExport.LoggedEntry(
                    title: title,
                    tmdbID: logged.movieID,
                    tier: tier.rawValue,
                    displayRank: index + 1,
                    score: scores[logged.id] ?? 0,
                    watchedDate: logged.watchedDate
                ))
            }
        }

        let watchlistExportEntries = watchlistEntries.map { entry in
            LibraryExport.WatchlistEntry(
                title: moviesByTmdbID[entry.movieID]?.title ?? "Unknown movie",
                tmdbID: entry.movieID,
                addedDate: entry.addedDate
            )
        }

        return LibraryExport(
            formatVersion: LibraryExport.currentFormatVersion,
            exportedDate: .now,
            loggedMovies: loggedExportEntries,
            watchlist: watchlistExportEntries
        )
    }

    /// Encodes `build(userID:modelContext:)` and writes it to a fresh file
    /// in the temporary directory, for handing to a share sheet. Returns
    /// `nil` only if encoding itself fails (never expected in practice --
    /// every field here is a plain, always-encodable type).
    static func exportToTemporaryFile(userID: UUID, modelContext: ModelContext) -> URL? {
        let export = build(userID: userID, modelContext: modelContext)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(export) else { return nil }

        let filename = "RankIt-Library-Export-\(ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
