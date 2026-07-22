import SwiftUI

struct AppCoordinatorView: View {
    @ObservedObject var appState: AppState
    let dependencies: DependencyContainer

    var body: some View {
        Group {
            switch appState.sessionState {
            case .loading:
                LaunchView()

            case .signedOut:
                signedOutFlow

            case .onboarding:
                OnboardingFlowView(
                    onComplete: {
                        appState.showSignedInApp()
                    }
                )

            case .signedIn:
                SignedInRootView(
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
                onComplete: {
                    appState.showSignedInApp()
                }
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
