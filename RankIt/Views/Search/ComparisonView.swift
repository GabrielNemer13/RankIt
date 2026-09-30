import SwiftUI
import SwiftData

struct ComparisonView: View {
    let movie: Movie
    let tier: MovieTier
    /// Pass the movie's existing `LoggedMovie` to re-rank it instead of
    /// logging a new one (see MovieDetailView's "Re-rank this movie").
    var reRankingExisting: LoggedMovie?
    /// See `TierPickerView.onFinished` -- threaded straight through so
    /// Discover's "Rank it" sheet can be dismissed once a rank is saved
    /// (or the user cancels), regardless of which screen in the flow
    /// that happens on.
    var onFinished: ((Bool) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: LogFlowViewModel?
    /// Drives the auto-navigate-to-detail behavior below. `nil` while
    /// nothing's been saved yet (or when `onFinished` is set -- Discover's
    /// "Rank it" sheet dismisses itself instead; see `SavedConfirmationView`).
    @State private var confirmedLoggedMovie: LoggedMovie?

    var body: some View {
        Group {
            if let viewModel {
                ComparisonContent(viewModel: viewModel, onFinished: onFinished, confirmedLoggedMovie: $confirmedLoggedMovie)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel?.isSaved == true)
        // Applies to Search's new-log flow, re-ranking, and tier-changing
        // alike (anywhere `onFinished` is nil -- see `SavedConfirmationView`):
        // after a beat, push the movie's detail screen showing the tier/rank
        // that was just saved, same as tapping it from Library would. Pushed
        // fresh rather than popping back to an already-open MovieDetailView
        // (which re-rank/tier-change could in principle return to directly)
        // so every entry point uses one mechanism instead of three.
        .navigationDestination(item: $confirmedLoggedMovie) { loggedMovie in
            MovieDetailView(movie: movie, context: .library(loggedMovie: loggedMovie))
        }
        .task {
            if viewModel == nil {
                let user = CurrentUserProvider.fetchOrCreateCurrentUser(in: modelContext)
                viewModel = LogFlowViewModel(
                    movie: movie,
                    tier: tier,
                    currentUser: user,
                    modelContext: modelContext,
                    reRanking: reRankingExisting
                )
            }
        }
    }

    /// Prefers the view model once it exists: it captures the movie's
    /// *original* tier at creation, so it stays correct even after `save()`
    /// mutates `reRankingExisting.tier` in place. Falls back to comparing
    /// the raw parameters only for the brief moment before `.task` creates
    /// it, when `reRankingExisting.tier` hasn't been touched yet either way.
    private var navigationTitleText: String {
        if let viewModel {
            if viewModel.isTierChange { return "Change Tier" }
            return viewModel.isReRanking ? "Re-rank" : "Compare"
        }
        guard let reRankingExisting else { return "Compare" }
        return reRankingExisting.tier != tier ? "Change Tier" : "Re-rank"
    }
}

private struct ComparisonContent: View {
    let viewModel: LogFlowViewModel
    var onFinished: ((Bool) -> Void)? = nil
    var confirmedLoggedMovie: Binding<LoggedMovie?>

    var body: some View {
        if viewModel.isSaved {
            SavedConfirmationView(viewModel: viewModel, onFinished: onFinished, confirmedLoggedMovie: confirmedLoggedMovie)
        } else if viewModel.isComplete {
            ResolutionView(viewModel: viewModel)
        } else {
            ComparisonPromptView(viewModel: viewModel)
        }
    }
}

private struct ComparisonPromptView: View {
    let viewModel: LogFlowViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Which did you like more?")
                .font(.headline)

            VStack(spacing: 12) {
                Button {
                    viewModel.chooseExisting()
                } label: {
                    Text(viewModel.currentComparisonTitle ?? "")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.chooseTie()
                } label: {
                    Text("Too hard to say")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.chooseNew()
                } label: {
                    Text(viewModel.movie.title)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                viewModel.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo)
        }
        .padding()
    }
}

private struct ResolutionView: View {
    let viewModel: LogFlowViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let tiedTitle = viewModel.tiedMovieTitle {
                Text("Tied with \u{201C}\(tiedTitle)\u{201D}")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            } else {
                Text("Ranking found!")
                    .font(.headline)
            }

            Button {
                viewModel.save()
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                viewModel.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo)

            Spacer()
        }
        .padding()
    }
}

private struct SavedConfirmationView: View {
    let viewModel: LogFlowViewModel
    var onFinished: ((Bool) -> Void)? = nil
    var confirmedLoggedMovie: Binding<LoggedMovie?>

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            if viewModel.isTierChange {
                Text("\(viewModel.movie.title) moved to \(viewModel.tier.rawValue.capitalized)")
                    .multilineTextAlignment(.center)
            } else if viewModel.isReRanking {
                Text("\(viewModel.movie.title) re-ranked in \(viewModel.tier.rawValue.capitalized)")
                    .multilineTextAlignment(.center)
            } else {
                Text("\(viewModel.movie.title) logged as \(viewModel.tier.rawValue.capitalized)")
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        // Auto-dismiss, one of two ways depending on how this flow was
        // reached. Either way: if the user manually navigates away before
        // the delay elapses, this view disappears and SwiftUI cancels the
        // task -- `try await Task.sleep` then throws instead of returning,
        // so the `catch` return bails out before either branch's followup
        // runs. Nothing here fights a manual dismissal.
        .task {
            do {
                if onFinished != nil {
                    try await Task.sleep(nanoseconds: 1_100_000_000)
                } else {
                    try await Task.sleep(nanoseconds: 1_800_000_000)
                }
            } catch {
                return // cancelled -- the user already navigated away
            }
            if let onFinished {
                // Discover's "Rank it" sheet: dismiss back to the feed at
                // the same card, never to a detail screen -- see
                // `TierPickerView.onFinished`'s doc comment.
                onFinished(true)
            } else {
                // Search's new-log flow, re-ranking, and tier-changing:
                // land on the movie's detail screen showing what was just
                // saved (see `ComparisonView`'s `.navigationDestination`).
                confirmedLoggedMovie.wrappedValue = viewModel.savedLoggedMovie
            }
        }
    }
}
