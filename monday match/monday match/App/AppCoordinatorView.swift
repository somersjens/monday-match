import SwiftUI

struct AppCoordinatorView: View {
    @ObservedObject var appState: AppState
    let dependencies: DependencyContainer

    @State private var onboardingErrorMessage: String?

    var body: some View {
        Group {
            switch appState.sessionState {
            case .loading:
                LaunchView()

            case .signedOut:
                signedOutFlow

            case .onboarding:
                OnboardingFlowView(
                    repository: dependencies.profileRepository,
                    onComplete: completeOnboarding
                )

            case .signedIn:
                SignedInRootView(
                    repository: dependencies.profileRepository,
                    onSignOut: {
                        Task {
                            await appState.signOut()
                        }
                    }
                )
            }
        }
        .task {
            guard appState.sessionState == .loading else { return }
            await appState.start()
        }
        .alert(
            "Could not save your profile",
            isPresented: Binding(
                get: { onboardingErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        onboardingErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(onboardingErrorMessage ?? "")
        }
    }

    /// Persists the onboarding result before entering the signed-in app.
    /// Without this the whole onboarding flow would be discarded.
    private func completeOnboarding(_ draft: ProfileDraft) {
        do {
            try dependencies.profileRepository.saveProfile(draft)
            appState.showSignedInApp()
        } catch {
            onboardingErrorMessage = error.localizedDescription
        }
    }

    private var signedOutFlow: some View {
        NavigationStack(path: $appState.navigationPath) {
            WelcomeView(
                onGetStarted: {
                    appState.navigationPath.append(.howItWorks)
                },
                onSignIn: {
                    appState.navigationPath.append(.signIn)
                }
            )
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .howItWorks:
            HowItWorksView(
                onContinue: {
                    appState.navigationPath.append(.earlyAccess)
                }
            )

        case .earlyAccess:
            EarlyAccessView(
                onClaimAccess: {
                    appState.navigationPath.append(.signIn)
                }
            )

        case .signIn:
            SignInPlaceholderView(
                authService: dependencies.authService,
                onAuthenticated: handleAuthenticatedSession
            )

        case .onboarding:
            OnboardingFlowView(
                repository: dependencies.profileRepository,
                onComplete: completeOnboarding
            )

        case .dashboard:
            DashboardView()

        case .profile:
            ProfileView(
                profile: .constant(.mockCompleted)
            )

        case .settings:
            SettingsView(
                onSignOut: {
                    Task {
                        await appState.signOut()
                    }
                },
                onDeleteLocalProfile: {}
            )
        }
    }

    private func handleAuthenticatedSession(
        _ session: RestoredSession
    ) {
        switch session {
        case .signedOut:
            break
        case .onboarding:
            appState.showOnboarding()
        case .signedIn:
            appState.showSignedInApp()
        }
    }
}
