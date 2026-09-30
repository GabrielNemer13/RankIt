import SwiftUI

struct TierPickerView: View {
    let movie: Movie
    /// Non-nil only when this flow was presented as a standalone sheet
    /// (see Discover's "Rank it" action) rather than pushed within an
    /// existing flow (Search's usage never sets this). Called with `true`
    /// once a rank is saved, `false` if the user cancels out -- either way
    /// the caller is expected to dismiss the sheet in response, which is
    /// also why a Cancel button only makes sense to show when this is set.
    var onFinished: ((Bool) -> Void)? = nil

    var body: some View {
        VStack(spacing: 24) {
            AsyncImage(url: movie.posterURL) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(movie.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("How did you feel about it?")
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                tierButton(.loved, label: "🟢 Loved")
                tierButton(.liked, label: "🟡 Liked")
                tierButton(.disliked, label: "🔴 Disliked")
            }
        }
        .padding()
        .navigationTitle("Rate It")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onFinished != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinished?(false) }
                }
            }
        }
    }

    private func tierButton(_ tier: MovieTier, label: String) -> some View {
        NavigationLink {
            ComparisonView(movie: movie, tier: tier, onFinished: onFinished)
        } label: {
            Text(label)
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

#Preview {
    NavigationStack {
        TierPickerView(movie: PreviewMovieCatalogService.sampleCatalog[0])
    }
}
