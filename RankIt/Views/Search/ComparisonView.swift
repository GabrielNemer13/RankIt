import SwiftUI
import SwiftData

struct ComparisonView: View {
    let movie: Movie
    let tier: MovieTier
    /// Pass the movie's existing `LoggedMovie` to re-rank it instead of
    /// logging a new one (see MovieDetailView's "Re-rank this movie").
    var reRankingExisting: LoggedMovie?

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: LogFlowViewModel?

    var body: some View {
        Group {
            if let viewModel {
                ComparisonContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel?.isSaved == true)
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

    var body: some View {
        if viewModel.isSaved {
            SavedConfirmationView(viewModel: viewModel)
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
    }
}
