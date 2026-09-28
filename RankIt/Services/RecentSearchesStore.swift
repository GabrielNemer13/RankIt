import Foundation

/// Persists the user's last ~10 distinct search queries. `UserDefaults`
/// fits better than a new SwiftData model here: it's a small, purely local
/// convenience list with no relationships, no need to sync via CloudKit,
/// and nothing else ever queries it.
struct RecentSearchesStore {
    private static let key = "RecentSearchesStore.queries"
    private static let limit = 10

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var queries: [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }

    /// Moves `query` to the front (case-insensitive de-dup against any
    /// existing entry), trimming to the most recent `limit` entries.
    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = queries
        current.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        current.insert(trimmed, at: 0)
        defaults.set(Array(current.prefix(Self.limit)), forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
