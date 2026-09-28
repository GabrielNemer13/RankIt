import SwiftUI

/// Lets the user move an existing Library movie into a different tier,
/// reusing `ComparisonView`'s `.reRank(existing:)` flow with a `tier`
/// different from the movie's current one -- see `LogFlowViewModel`'s
/// `isTierChange`. Reached only from `MovieDetailView`'s `.library` context.
struct ChangeTierView: View {
    let movie: Movie
    let loggedMovie: LoggedMovie

    var body: some View {
        VStack(spacing: 24) {
            Text(movie.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("Move to a different tier")
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                ForEach(MovieTier.allCases, id: \.self) { tier in
                    tierButton(tier)
                }
            }
        }
        .padding()
        .navigationTitle("Change Tier")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func tierButton(_ tier: MovieTier) -> some View {
        let label = "\(tier.emoji) \(tier.rawValue.capitalized)"
        if tier == loggedMovie.tier {
            Text(label)
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.tertiary)
        } else {
            NavigationLink {
                ComparisonView(movie: movie, tier: tier, reRankingExisting: loggedMovie)
            } label: {
                Text(label)
                    .font(.title3)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChangeTierView(
            movie: PreviewMovieCatalogService.sampleCatalog[0],
            loggedMovie: LoggedMovie(userID: UUID(), movieID: PreviewMovieCatalogService.sampleCatalog[0].tmdbID, tier: .loved, rankPosition: 0)
        )
    }
}
