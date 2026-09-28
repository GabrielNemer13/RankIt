import SwiftUI

/// Poster thumbnail + title/year + TMDb rating row, shared by Library and
/// Watchlist. `leading` is an optional accessory in front of the poster
/// (Library uses it for the "#N" rank badge; Watchlist has none).
struct MoviePosterRow<Leading: View>: View {
    let movie: Movie?
    /// The signed-in user's own rating for this movie (see `RatingScore`),
    /// shown alongside TMDb's when present. `nil` for rows that aren't
    /// ranked yet -- Watchlist entries and Search results.
    var myScore: Double? = nil
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 12) {
            leading()

            AsyncImage(url: movie?.posterURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(movie?.title ?? "Unknown movie")
                    .font(.headline)
                    .lineLimit(2)
                if let movie, movie.year > 0 {
                    Text(String(movie.year))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let myScore {
                    Label(String(format: "%.1f", myScore), systemImage: "person.fill")
                        .foregroundStyle(.tint)
                }
                if let movie, movie.voteAverage > 0 {
                    Label(String(format: "%.1f", movie.voteAverage), systemImage: "star.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .labelStyle(.titleAndIcon)
            .fixedSize()
            // A secondary badge, not primary reading content -- capped so
            // it can't balloon large enough to crowd out the row's title
            // or the disclosure chevron.
            .dynamicTypeSize(...DynamicTypeSize.large)
        }
    }
}

extension MoviePosterRow where Leading == EmptyView {
    init(movie: Movie?, myScore: Double? = nil) {
        self.movie = movie
        self.myScore = myScore
        self.leading = { EmptyView() }
    }
}
