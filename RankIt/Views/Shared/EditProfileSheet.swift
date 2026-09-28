import SwiftUI

/// View/edit display name and username after onboarding. Reached from the
/// Friends tab's toolbar. Shares `ProfileEditViewModel` with onboarding's
/// profile step, so validation is identical.
struct EditProfileSheet: View {
    let user: User

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ProfileEditViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    EditProfileForm(viewModel: viewModel, onSaved: { dismiss() })
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = ProfileEditViewModel(user: user, modelContext: modelContext)
            }
        }
    }
}

private struct EditProfileForm: View {
    @Bindable var viewModel: ProfileEditViewModel
    let onSaved: () -> Void

    @State private var showErrors = false
    #if DEBUG
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    #endif

    private var usernameBinding: Binding<String> {
        Binding(
            get: { viewModel.username },
            set: { viewModel.username = $0.lowercased() }
        )
    }

    var body: some View {
        Form {
            Section("Display Name") {
                TextField("Display Name", text: $viewModel.displayName)
                if showErrors, let error = viewModel.displayNameError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Username") {
                TextField("Username", text: usernameBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if showErrors, let error = viewModel.usernameError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            #if DEBUG
            Section {
                Button("Reset Onboarding", role: .destructive) {
                    hasCompletedOnboarding = false
                    onSaved()
                }
            } footer: {
                Text("Debug only: re-runs the first-run onboarding flow next launch.")
            }
            #endif
        }
        .onChange(of: viewModel.displayName) { showErrors = true }
        .onChange(of: viewModel.username) { showErrors = true }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    showErrors = true
                    if viewModel.save() {
                        onSaved()
                    }
                }
            }
        }
    }
}

#Preview {
    EditProfileSheet(user: User(username: "me", displayName: "Me"))
        .modelContainer(for: [User.self], inMemory: true)
}
