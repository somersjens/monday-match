import SwiftUI

struct AppCoordinatorView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var access: LifetimeAccessStore
    @Environment(\.scenePhase) private var scenePhase
    let dependencies: DependencyContainer

    /// Codes the app was opened with, for instance from the Camera app.
    @StateObject private var codeInbox = ProfileCodeInbox()
    @State private var showsWelcomeFromAccess = false

    var body: some View {
        Group {
            switch appState.sessionState {
            case .loading:
                LaunchView()

            case .signedOut:
                welcomeFlow

            case .onboarding, .signedIn:
                if access.hasAccess {
                    if dependencies.profileCreationStore.load()?.completedAt != nil {
                        welcomeFlow
                    } else {
                        onboardingFlow
                    }
                } else {
                    accessRequiredFlow
                }
            }
        }
        .background(Color("WelcomeBackground").ignoresSafeArea())
        .overlay(alignment: .top) {
            ProfileCodeNoticeBanner(inbox: codeInbox)
        }
        .onOpenURL { url in
            codeInbox.open(url, isProfileReady: dependencies.profileCreationStore.load()?.canShareProfile == true)
        }
        .task {
            guard appState.sessionState == .loading else { return }
            access.updateCompletion(savedCompletionDate)
            await appState.start()
            // Session restoration can restore a profile from Supabase too.
            access.updateCompletion(savedCompletionDate)
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
    }

    /// Accounts without a finished profile go through the profile creation
    /// questionnaire; once it is done the welcome screen takes over.
    private var onboardingFlow: some View {
        ProfileCreationGateView(
            store: dependencies.profileCreationStore,
            repository: dependencies.profileRepository,
            onComplete: {
                access.updateCompletion(savedCompletionDate)
                appState.showSignedInApp()
            },
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
            welcomeFlow
        } else {
            EarlyAccessView(access: access, onContinue: {}, onBack: {
                showsWelcomeFromAccess = true
            })
        }
    }

    private var welcomeFlow: some View {
        NavigationStack(path: $appState.navigationPath) {
            WelcomeView(
                profileCreationStore: dependencies.profileCreationStore,
                repository: dependencies.profileRepository,
                access: access,
                automaticallyShowsAccessOnAppear: !showsWelcomeFromAccess,
                authService: dependencies.authService,
                hasAccount: appState.sessionState == .signedIn || appState.sessionState == .onboarding,
                profileSync: dependencies.profileSync,
                chatRepository: dependencies.chatRepository,
                photoVerification: dependencies.photoVerification,
                codeInbox: codeInbox,
                onDeleteProfile: deleteProfile,
                onProfileDeleted: {
                    access.updateCompletion(nil)
                    appState.showWelcomeAfterProfileDeletion()
                },
                onAccountCreated: appState.showSignedInApp,
                onSignIn: {
                    appState.navigationPath.append(.signIn)
                }
            )
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
        }
        // A deleted profile leaves nothing of the old screens behind.
        .id(appState.profileGeneration)
    }

    private func deleteProfile() async throws {
        let deletion = dependencies.profileDeletion
        // Closing Apple's sheet cancels the deletion before anything is removed.
        let appleCode = await deletion.needsAppleAuthorization
            ? try await AppleReauthorization().authorizationCode() : nil
        try await deletion.deleteProfile(appleAuthorizationCode: appleCode)
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
            if savedCompletionDate != nil {
                appState.showSignedInApp()
            } else {
                appState.showOnboarding()
            }
        case .signedIn:
            appState.showSignedInApp()
        }
    }
}
