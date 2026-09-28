import SwiftUI

/// First-run onboarding: a small paged flow shown once (gated by
/// `hasCompletedOnboarding` in `RootTabView`) before the tab bar. Skip is
/// available on every screen. The profile step updates the placeholder
/// `User` that `CurrentUserProvider` already created rather than making a
/// new one -- see `ProfileEditViewModel`.
struct OnboardingView: View {
    let currentUser: User
    /// Called when onboarding finishes, either by completing the last
    /// step or by tapping Skip. `startingTab` is non-nil only when the
    /// starter step's "Log your first movie" / "Explore trending" actions
    /// were used, so `RootTabView` can land on that tab instead of the
    /// default.
    let onComplete: (_ startingTab: AppTab?) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var step: Step = .welcome
    @State private var profileViewModel: ProfileEditViewModel?

    private enum Step: Int, CaseIterable {
        case welcome, ranking, profile, starter
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                OnboardingProgressView(currentStep: step.rawValue, totalSteps: Step.allCases.count)
                Spacer()
                Button("Skip") { onComplete(nil) }
                    .foregroundStyle(.secondary)
            }
            .padding()

            Group {
                switch step {
                case .welcome:
                    WelcomeStepView()
                case .ranking:
                    RankingExplainerStepView()
                case .profile:
                    if let profileViewModel {
                        ProfileStepView(viewModel: profileViewModel, onContinue: advance)
                    } else {
                        ProgressView()
                    }
                case .starter:
                    StarterStepView(
                        onLogMovie: { onComplete(.search) },
                        onExploreTrending: { onComplete(.discover) }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if step == .welcome || step == .ranking {
                Button("Continue") { advance() }
                    .buttonStyle(.borderedProminent)
                    .padding()
            }
        }
        .task {
            if profileViewModel == nil {
                profileViewModel = ProfileEditViewModel(user: currentUser, modelContext: modelContext)
            }
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            onComplete(nil)
            return
        }
        step = next
    }
}

private struct OnboardingProgressView: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == currentStep ? 20 : 8, height: 8)
            }
        }
        .animation(.default, value: currentStep)
    }
}

private struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Welcome to RankIt")
                .font(.largeTitle.bold())
            Text("Log every movie you watch and rank it against the others in its tier, so your favorites are always in the right order.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
    }
}

private struct RankingExplainerStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("How Ranking Works")
                .font(.title2.bold())
            Text("Log a movie into a tier, then answer a few quick head-to-head comparisons to find its exact spot.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            HStack(spacing: 16) {
                tierBadge(emoji: "🟢", label: "Loved")
                tierBadge(emoji: "🟡", label: "Liked")
                tierBadge(emoji: "🔴", label: "Disliked")
            }

            ComparisonIllustration()

            Spacer()
        }
        .padding()
    }

    private func tierBadge(emoji: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.title2)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A small static illustration of the comparison screen, built entirely
/// from SwiftUI shapes/text -- no image asset.
private struct ComparisonIllustration: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Which did you like more?")
                .font(.subheadline.bold())
            HStack(spacing: 16) {
                posterPlaceholder()
                Text("vs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                posterPlaceholder()
            }
            Text("Too hard to say")
                .font(.caption)
                .foregroundStyle(.tint)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func posterPlaceholder() -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .frame(width: 64, height: 96)
    }
}

private struct ProfileStepView: View {
    @Bindable var viewModel: ProfileEditViewModel
    let onContinue: () -> Void

    @State private var showErrors = false

    private var usernameBinding: Binding<String> {
        Binding(
            get: { viewModel.username },
            set: { viewModel.username = $0.lowercased() }
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Create Your Profile")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Display Name").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. Jamie Rivera", text: $viewModel.displayName)
                    .textFieldStyle(.roundedBorder)
                if showErrors, let error = viewModel.displayNameError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 6) {
                Text("Username").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. jamie_r", text: usernameBinding)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if showErrors, let error = viewModel.usernameError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.horizontal)

            Button("Continue") {
                showErrors = true
                if viewModel.save() {
                    onContinue()
                }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
        .onChange(of: viewModel.displayName) { showErrors = true }
        .onChange(of: viewModel.username) { showErrors = true }
    }
}

private struct StarterStepView: View {
    let onLogMovie: () -> Void
    let onExploreTrending: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Ready to get started?")
                .font(.title2.bold())
            Text("Jump right in, or just explore -- you can always do this later.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(spacing: 16) {
                Button("Log your first movie", action: onLogMovie)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("Explore trending", action: onExploreTrending)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    OnboardingView(currentUser: User(username: "me", displayName: "Me")) { _ in }
        .modelContainer(for: [User.self], inMemory: true)
}
