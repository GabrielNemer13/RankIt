import SwiftUI

/// TMDb's API terms (themoviedb.org/api-terms-of-use, section 3,
/// "Attribution") require: their logo, sized/placed so it reads as
/// *less prominent* than RankIt's own branding elsewhere in the app; the
/// exact notice below; and no wording implying an official partnership.
/// TMDb doesn't publish numeric clear-space/minimum-size specs (checked
/// themoviedb.org/about/logos-attribution) -- their requirement is
/// qualitative, so `TMDbLogo`'s size and surrounding padding here are
/// deliberately modest, well under any of RankIt's own branding moments
/// (e.g. the onboarding app icon).
///
/// `TMDbLogo` in Assets.xcassets is TMDb's official "primary short (blue)"
/// SVG (from the logos-attribution page above), rendered to PNG at 1x/2x/3x
/// via AppKit (which reads SVG's intrinsic size correctly, unlike a plain
/// QuickLook thumbnail render) -- see the asset's source SVG for exact
/// colors if it ever needs re-exporting.
struct AboutView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image("TMDbLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 140)
                            .accessibilityLabel("The Movie Database")
                        Text("This product uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                }

                Section {
                    LabeledContent("Movie data & artwork", value: "The Movie Database (TMDB)")
                    LabeledContent("Trailers", value: "Official YouTube uploads only")
                }

                Section {
                    Text("RankIt is a personal movie-ranking app. It is not affiliated with, sponsored by, or endorsed by TMDB.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    AboutView()
}
