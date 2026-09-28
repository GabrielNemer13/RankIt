import Foundation

/// Deterministic, offline stand-in for `TMDbClient` — used by SwiftUI
/// previews, and to exercise the Log flow UI end-to-end without a live
/// network connection or a configured TMDb API key.
struct PreviewMovieCatalogService: MovieCatalogServicing {
    private let catalog: [Movie]

    init(catalog: [Movie] = PreviewMovieCatalogService.sampleCatalog) {
        self.catalog = catalog
    }

    func searchMovies(query: String) async throws -> [Movie] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return catalog.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    func movieDetails(id: Int) async throws -> Movie {
        guard let movie = catalog.first(where: { $0.tmdbID == id }) else {
            throw TMDbError.invalidResponse
        }
        return movie
    }

    func trending() async throws -> [Movie] {
        catalog
    }

    func officialTrailers(movieID: Int) async throws -> [Trailer] {
        []
    }

    static let sampleCatalog: [Movie] = [
        Movie(
            tmdbID: 27205, title: "Inception", year: 2010,
            genres: ["Science Fiction", "Action"], voteAverage: 8.4,
            overview: "A thief who steals corporate secrets through dream-sharing technology is given the inverse task of planting an idea into the mind of a C.E.O.",
            cast: ["Leonardo DiCaprio", "Joseph Gordon-Levitt", "Elliot Page", "Tom Hardy"]
        ),
        Movie(
            tmdbID: 155, title: "The Dark Knight", year: 2008,
            genres: ["Action", "Crime", "Drama"], voteAverage: 8.5,
            overview: "Batman raises the stakes in his war on crime with the help of Lt. Jim Gordon and District Attorney Harvey Dent, but a new criminal mastermind known as the Joker throws Gotham into chaos.",
            cast: ["Christian Bale", "Heath Ledger", "Aaron Eckhart", "Michael Caine"]
        ),
        Movie(
            tmdbID: 372058, title: "Your Name.", year: 2016,
            genres: ["Animation", "Drama", "Romance"], voteAverage: 8.5,
            overview: "Mitsuha and Taki are complete strangers living separate lives, until they suddenly start swapping bodies, connecting them in a bond that transcends time.",
            cast: ["Ryunosuke Kamiki", "Mone Kamishiraishi"]
        ),
        Movie(
            tmdbID: 13, title: "Forrest Gump", year: 1994,
            genres: ["Comedy", "Drama", "Romance"], voteAverage: 8.5,
            overview: "A man with a low IQ has accomplished great things in his life and been present during significant historic events — in each case, far exceeding what anyone imagined he could do.",
            cast: ["Tom Hanks", "Robin Wright", "Gary Sinise"]
        ),
        Movie(
            tmdbID: 550, title: "Fight Club", year: 1999,
            genres: ["Drama"], voteAverage: 8.4,
            overview: "An insomniac office worker and a devil-may-care soap maker form an underground fight club that evolves into something much, much more.",
            cast: ["Edward Norton", "Brad Pitt", "Helena Bonham Carter"]
        ),
        Movie(
            tmdbID: 129, title: "Spirited Away", year: 2001,
            genres: ["Animation", "Family", "Fantasy"], voteAverage: 8.5,
            overview: "A young girl, Chihiro, becomes trapped in a strange new world of spirits. When her parents undergo a mysterious transformation, she must call upon the courage she never knew she had.",
            cast: ["Rumi Hiiragi", "Miyu Irino"]
        )
    ]
}
