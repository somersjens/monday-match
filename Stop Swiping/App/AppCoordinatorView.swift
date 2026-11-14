import SwiftUI

struct AppCoordinatorView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var access: LifetimeAccessStore
    @Environment(\.scenePhase) private var scenePhase
    let dependencies: DependencyContainer

    @State private var onboardingErrorMessage: String?
    @State private var showsWelcomeFromAccess = false

    var body: some View {
        Group {
            switch appState.sessionState {
            case .loading:
                LaunchView()

            case .signedOut:
                signedOutFlow

            case .onboarding:
                if access.hasAccess {
                    onboardingFlow
                } else {
                    accessRequiredFlow
                }

            case .signedIn:
                if access.hasAccess {
                    SignedInRootView(
                        repository: dependencies.profileRepository,
                        onSignOut: {
                            Task {
                                await appState.signOut()
                            }
                        }
                    )
                } else {
                    accessRequiredFlow
                }
            }
        }
        .background(Color("WelcomeBackground").ignoresSafeArea())
        .task {
            guard appState.sessionState == .loading else { return }
            access.updateCompletion(savedCompletionDate)
            await appState.start()
            await access.start()
        }
        .onChange(of: access.hasAccess) { _, allowed in
            if allowed { showsWelcomeFromAccess = false }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                access.updateCompletion(savedCompletionDate)
                await access.start()
            }
        }
        .alert(
            L10n("Could not save your profile"),
            isPresented: Binding(
                get: { onboardingErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        onboardingErrorMessage = nil
                    }
                }
            )
        ) {
            Button(L10n("OK"), role: .cancel) {}
        } message: {
            Text(onboardingErrorMessage ?? "")
        }
    }

    /// Persists the onboarding result before entering the signed-in app.
    /// Without this the whole onboarding flow would be discarded.
    private func completeOnboarding(_ draft: ProfileDraft) {
        do {
            try dependencies.profileRepository.saveProfile(draft)
            access.updateCompletion(draft.profileCreationCompletedAt ?? Date())
            if access.hasAccess { appState.showSignedInApp() }
        } catch {
            onboardingErrorMessage = error.localizedDescription
        }
    }

    private var onboardingFlow: some View {
        OnboardingFlowView(
            repository: dependencies.profileRepository,
            profileCreationStore: dependencies.profileCreationStore,
            onComplete: completeOnboarding,
            // An underage answer ends the session; the landing page then
            // shows the lock from the shared profile-creation state.
            onUnderage: {
                Task {
                    await appState.signOut()
                }
            }
        )
    }

    @ViewBuilder
    private var accessRequiredFlow: some View {
        if showsWelcomeFromAccess {
            signedOutFlow
        } else {
            EarlyAccessView(access: access, onContinue: {}, onBack: {
                showsWelcomeFromAccess = true
            })
        }
    }

    private var signedOutFlow: some View {
        NavigationStack(path: $appState.navigationPath) {
            WelcomeView(
                profileCreationStore: dependencies.profileCreationStore,
                repository: dependencies.profileRepository,
                access: access,
                automaticallyShowsAccessOnAppear: !showsWelcomeFromAccess,
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
                access: access,
                onContinue: {
                    appState.navigationPath.append(.signIn)
                }
            )

        case .signIn:
            SignInPlaceholderView(
                authService: dependencies.authService,
                onAuthenticated: handleAuthenticatedSession
            )

        case .onboarding:
            onboardingFlow

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

    private var savedCompletionDate: Date? {
        dependencies.profileCreationStore.load()?.completedAt
            ?? ((try? dependencies.profileRepository.loadProfile()) ?? nil)?.profileCreationCompletedAt
    }

    private func handleAuthenticatedSession(
        _ session: RestoredSession
    ) {
        access.updateCompletion(savedCompletionDate)
        switch session {
        case .signedOut:
            break
        case .onboarding:
            if OnboardingViewModel(repository: dependencies.profileRepository).isReadyToComplete {
                appState.showSignedInApp()
            } else {
                appState.showOnboarding()
            }
        case .signedIn:
            appState.showSignedInApp()
        }
    }
}
