import Foundation

/// Which actions `MovieDetailView` should show for a given context, as a
/// pure decision separate from the view -- so the read-only guard (and the
/// library/watchlist action sets) are unit-testable without SwiftUI.
struct DetailActions: Equatable {
    var removeButtonTitle: String?
    var canViewComparisonHistory: Bool
    var canReRank: Bool
    var canChangeTier: Bool

    /// True whenever there's a destructive removal action at all.
    var canRemove: Bool { removeButtonTitle != nil }

    static func available(for context: MovieDetailContext) -> DetailActions {
        switch context {
        case .library:
            return DetailActions(
                removeButtonTitle: "Remove from Library",
                canViewComparisonHistory: true,
                canReRank: true,
                canChangeTier: true
            )
        case .watchlist:
            return DetailActions(
                removeButtonTitle: "Remove from Watchlist",
                canViewComparisonHistory: false,
                canReRank: false,
                canChangeTier: false
            )
        case .readOnly:
            return DetailActions(
                removeButtonTitle: nil,
                canViewComparisonHistory: false,
                canReRank: false,
                canChangeTier: false
            )
        }
    }
}
