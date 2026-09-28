import SwiftUI

struct TierPickerView: View {
    let movie: Movie

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
    }

    private func tierButton(_ tier: MovieTier, label: String) -> some View {
        NavigationLink {
            ComparisonView(movie: movie, tier: tier)
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
