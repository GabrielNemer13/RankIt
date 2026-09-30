import SwiftUI
import SwiftData

struct DiscoverView: View {
    let currentUser: User

    @Environment(\.movieCatalogService) private var catalogService
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: DiscoverViewModel?
    @State private var scrollPosition: Int?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    DiscoverFeed(viewModel: viewModel, scrollPosition: $scrollPosition)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Discover")
            .toolbar {
                if let viewModel {
                    ToolbarItem(placement: .topBarTrailing) {
                        GenreFilterMenu(viewModel: viewModel)
                    }
                }
            }
        }
        .task {
            if viewModel == nil {
                let vm = DiscoverViewModel(catalogService: catalogService, currentUser: currentUser, modelContext: modelContext)
                viewModel = vm
                await vm.loadIfNeeded()
            }
        }
    }
}

private struct GenreFilterMenu: View {
    @Bindable var viewModel: DiscoverViewModel

    var body: some View {
        Menu {
            Button("All Genres") { viewModel.selectedGenre = nil }
            ForEach(viewModel.availableGenres, id: \.self) { genre in
                Button(genre) { viewModel.selectedGenre = genre }
            }
        } label: {
            Label(viewModel.selectedGenre ?? "All", systemImage: "line.3.horizontal.decrease.circle")
        }
        .disabled(viewModel.availableGenres.isEmpty)
    }
}

private struct DiscoverFeed: View {
    @Bindable var viewModel: DiscoverViewModel
    @Binding var scrollPosition: Int?
    /// Drives the "Rank it" sheet. Kept separate from `rankedCandidate`
    /// below so the sheet's content always knows which movie it's for,
    /// independent of whether that rank actually gets saved.
    @State private var rankingCandidate: DiscoverCandidate?
    /// Set right before `rankingCandidate` is cleared, only if the flow
    /// actually saved a rank (as opposed to the user cancelling out) --
    /// consumed in `onDismiss` once the sheet has visually closed, so
    /// `DiscoverViewModel.markRanked` never runs concurrently with the
    /// dismiss animation.
    @State private var rankedCandidate: DiscoverCandidate?

    var body: some View {
        Group {
            if viewModel.isLoading, viewModel.candidates.isEmpty {
                ProgressView("Loading trailers…")
            } else if let errorMessage = viewModel.errorMessage, viewModel.candidates.isEmpty {
                ContentUnavailableView(
                    "Couldn't load Discover",
                    systemImage: "wifi.slash",
                    description: Text(errorMessage)
                )
            } else if viewModel.visibleCandidates.isEmpty {
                ContentUnavailableView(
                    "Nothing to discover",
                    systemImage: "film",
                    description: Text("Check back later, or try a different genre.")
                )
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.visibleCandidates) { candidate in
                            DiscoverCardView(
                                candidate: candidate,
                                isWatchlisted: viewModel.watchlistedMovieIDs.contains(candidate.movie.tmdbID),
                                onToggleWatchlist: { viewModel.toggleWatchlist(for: candidate) },
                                onRankIt: { rankingCandidate = candidate }
                            )
                            .containerRelativeFrame(.vertical)
                            .id(candidate.id)
                            .onAppear {
                                viewModel.loadMoreIfNeeded(currentCandidate: candidate)
                            }
                        }
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 80)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrollPosition)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        // A sheet (rather than pushing onto Discover's own NavigationStack)
        // means cancelling is just the standard swipe-to-dismiss, and
        // finishing -- either way -- always drops the user back on this
        // exact feed, scroll position untouched, with no extra plumbing.
        .sheet(item: $rankingCandidate, onDismiss: {
            if let rankedCandidate {
                viewModel.markRanked(rankedCandidate)
                self.rankedCandidate = nil
            }
        }) { candidate in
            NavigationStack {
                TierPickerView(movie: candidate.movie) { didSave in
                    if didSave { rankedCandidate = candidate }
                    rankingCandidate = nil
                }
            }
        }
    }
}

private struct DiscoverCardView: View {
    let candidate: DiscoverCandidate
    /// Sourced from `DiscoverViewModel.watchlistedMovieIDs`, not local
    /// `@State` -- this card's underlying view can be recreated by the
    /// `LazyVStack` as the user scrolls away and back, so the filled/empty
    /// state has to live in the view model to render correctly on that
    /// first reappearance rather than resetting to empty.
    let isWatchlisted: Bool
    let onToggleWatchlist: () -> Void
    let onRankIt: () -> Void

    @State private var isPlaying = true
    @State private var embedFailed = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            content
        }
        .contentShape(Rectangle())
        .onTapGesture { isPlaying.toggle() }
    }

    /// Capped below the accessibility Dynamic Type range: this is a
    /// fixed-size full-bleed video card, not a reading surface, and at
    /// accessibility sizes the huge title/placeholder text collided with
    /// each other (title overlay vs. the centered "No trailer" message).
    /// Still scales normally up through the standard sizes.
    private var content: some View {
        ZStack {
            if let trailer = candidate.trailer, !embedFailed {
                YouTubePlayerView(youtubeKey: trailer.youtubeKey, isPlaying: $isPlaying) {
                    embedFailed = true
                }
                .allowsHitTesting(false)
            } else if let trailer = candidate.trailer {
                // The uploader disabled embedding -- rather than a blank
                // black card, offer a direct link out to YouTube.
                Rectangle().fill(.black)
                VStack(spacing: 12) {
                    Text("This trailer can't be played here")
                        .foregroundStyle(.white.opacity(0.8))
                    Button("Open in YouTube") {
                        if let url = URL(string: "https://www.youtube.com/watch?v=\(trailer.youtubeKey)") {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            } else {
                Rectangle().fill(.black)
                Text("No trailer available")
                    .foregroundStyle(.white.opacity(0.6))
            }

            VStack {
                Spacer()
                ZStack(alignment: .bottom) {
                    // The trailer frame behind this text can be any
                    // brightness, so white text needs a guaranteed-dark
                    // scrim under it rather than relying on the video
                    // itself for contrast.
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 260)
                    .allowsHitTesting(false)

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.movie.title)
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                            if !candidate.movie.genres.isEmpty {
                                Text(candidate.movie.genres.prefix(3).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        Spacer()
                        VStack(spacing: 22) {
                            actionButton(systemImage: "star.fill", label: "Rank it", action: onRankIt)
                            watchlistButton
                        }
                    }
                    .padding()
                    // Extra clearance so title/actions clear the floating tab
                    // bar — the video background still extends full-bleed
                    // behind it (see .ignoresSafeArea on the containing feed).
                    // 170 rather than a smaller value: with two stacked
                    // action buttons instead of one, the lower button
                    // (Watchlist) landed in a band close to the bottom edge
                    // where simulator taps were reliably swallowed before
                    // they reached any gesture recognizer at all (not even
                    // the card's own play/pause tap) -- consistent with the
                    // same near-edge system-gesture interference documented
                    // for the floating tab bar elsewhere in this app. This
                    // much clearance keeps both buttons well clear of it.
                    .padding(.bottom, 170)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func actionButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Its own view (rather than another `actionButton` call) because it
    /// needs two things a plain icon button doesn't: a symbol that swaps
    /// between empty/filled based on `isWatchlisted` -- driven by the view
    /// model, so it's correct even if this card is a freshly-recreated
    /// instance from `LazyVStack` scroll recycling -- and a bounce tied to
    /// that same value, so the tap reads as acknowledged rather than a
    /// silent state flip.
    private var watchlistButton: some View {
        Button(action: onToggleWatchlist) {
            VStack(spacing: 4) {
                Image(systemName: isWatchlisted ? "bookmark.fill" : "bookmark")
                    .font(.title)
                    .symbolEffect(.bounce, value: isWatchlisted)
                Text("Watchlist")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
