import SwiftUI

struct SignedInRootView: View {
    @StateObject private var viewModel: SignedInRootViewModel

    let onSignOut: () -> Void

    init(
        repository: ProfileRepository,
        onSignOut: @escaping () -> Void
    ) {
        self.onSignOut = onSignOut

        // The repository is injected so this view reads the same store that
        // onboarding wrote to, instead of creating a second one.
        _viewModel = StateObject(
            wrappedValue: SignedInRootViewModel(
                repository: repository
            )
        )
    }

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(SignedInTab.dashboard)

            MatchResultContainerView(
                result: viewModel.matchResult,
                chatViewModel: viewModel.chatViewModel,
                onClearResult: viewModel.clearMatch
            )
            .tabItem {
                Label("Match", systemImage: "heart")
            }
            .tag(SignedInTab.match)

            ProfileView(
                profile: Binding(
                    get: { viewModel.profile },
                    set: { viewModel.updateProfile($0) }
                )
            )
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .tag(SignedInTab.profile)

            SettingsView(
                onSignOut: onSignOut,
                onDeleteLocalProfile: viewModel.deleteLocalProfile
            )
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(SignedInTab.settings)
        }
        .tint(AppColors.accent)
        .task {
            viewModel.loadProfile()
        }
        .alert(
            "Local storage error",
            isPresented: Binding(
                get: { viewModel.storageErrorMessage != nil },
                set: {
                    if !$0 {
                        viewModel.storageErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.storageErrorMessage ?? "")
        }
    }
}
