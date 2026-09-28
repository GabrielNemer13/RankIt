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
                            DiscoverCardView(candidate: candidate) { action in
                                viewModel.record(action: action, for: candidate)
                            }
                            .containerRelativeFrame(.vertical)
                            .id(candidate.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrollPosition)
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

private struct DiscoverCardView: View {
    let candidate: DiscoverCandidate
    let onAction: (DiscoverAction) -> Void

    @State private var isPlaying = true

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
            if let trailer = candidate.trailer {
                YouTubePlayerView(youtubeKey: trailer.youtubeKey, isPlaying: $isPlaying)
                    .allowsHitTesting(false)
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
                            actionButton(systemImage: "bookmark.fill", label: "Watchlist") {
                                onAction(.watchlisted)
                            }
                        }
                    }
                    .padding()
                    // Extra clearance so title/actions clear the floating tab
                    // bar — the video background still extends full-bleed
                    // behind it (see .ignoresSafeArea on the containing feed).
                    .padding(.bottom, 110)
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
        }
    }
}
