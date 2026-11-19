import SwiftUI

struct AppCoordinatorView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var access: LifetimeAccessStore
    @ObservedObject var notifications: NotificationEngine
    @Environment(\.scenePhase) private var scenePhase
    let dependencies: DependencyContainer

    /// Codes the app was opened with, for instance from the Camera app.
    @StateObject private var codeInbox = ProfileCodeInbox()
    /// Every launch opens on the welcome screen, also when an account stored
    /// on this phone (a reinstall keeps it in the Keychain) has no access:
    /// the access screen follows from there. Only once someone has moved on
    /// to the questionnaire does losing access take over the whole screen.
    @State private var showsWelcomeFromAccess = true
    /// Starts the welcome screen over after a returning account signs in, so
    /// it opens on the profile that came back with it.
    @State private var welcomeGeneration = 0
    /// The welcome light's shaders, compiled in the background during launch.
    @State private var isLightReady = false
    /// StoreKit's local entitlements normally answer within moments; never
    /// hold the launch screen longer than this for them.
    @State private var stopsWaitingForAccess = false

    private enum Screen {
        case loading, welcome, onboarding, accessRequired
    }

    /// The welcome screen stays one screen whether or not an account is
    /// signed in, so creating an account from it doesn't rebuild it.
    private var screen: Screen {
        guard isLightReady else { return .loading }
        switch appState.sessionState {
        case .loading:
            return .loading
        case .signedOut:
            return .welcome
        case .onboarding, .signedIn:
            // Without its entitlements an account would flash the access screen.
            guard access.isReady || stopsWaitingForAccess else { return .loading }
            guard access.hasAccess else { return showsWelcomeFromAccess ? .welcome : .accessRequired }
            return dependencies.profileCreationStore.load()?.completedAt != nil ? .welcome : .onboarding
        }
    }

    var body: some View {
        Group {
            switch screen {
            case .loading:
                LaunchView()
            case .welcome:
                welcomeFlow
            case .onboarding:
                onboardingFlow
                    .onAppear { showsWelcomeFromAccess = false }
            case .accessRequired:
                EarlyAccessView(access: access, onContinue: {}, onBack: {
                    showsWelcomeFromAccess = true
                }, questionnaireProgress: savedQuestionnaireProgress)
            }
        }
        .background(Color("WelcomeBackground").ignoresSafeArea())
        .overlay(alignment: .top) {
            ProfileCodeNoticeBanner(inbox: codeInbox)
        }
        .overlay(alignment: .top) {
            NotificationNoticeBanner(engine: notifications)
        }
        .environment(\.notificationEngine, notifications)
        .onOpenURL { url in
            if let destination = NotificationDestination(url: url) {
                notifications.pendingDestination = destination
                return
            }
            codeInbox.open(url, isProfileReady: dependencies.profileCreationStore.load()?.canShareProfile == true)
        }
        .task {
            appState.willSignOut = { [notifications, access] in
                LiveMatchCenter.clearAccountCache()
                access.disconnectServer()
                await notifications.accountSignedOut()
            }
        }
        .onChange(of: AppLanguageSettings.shared.language) { _, _ in
            // Pending notifications and the server's copy follow the app's language.
            Task { await notifications.sync() }
        }
        .task(id: notificationAccountState) {
            notifications.update(hasAccount: notificationAccountState.hasAccount,
                                 earlyAccessReminderAt: notificationAccountState.earlyAccessReminderAt)
        }
        .task(id: notificationAccountState.hasAccount) {
            // Lifetime access then belongs to the account, not only this iPhone.
            guard notificationAccountState.hasAccount else { return }
            await access.connectServer(dependencies.storeEntitlements)
        }
        .task {
            guard appState.sessionState == .loading else { return }
            access.updateCompletion(savedCompletionDate)
            // The audio session comes up while the light prepares, so the
            // entrance cue doesn't have to activate it on the main thread.
            SoundPlayer.shared.startSession()
            // Shaders, StoreKit and the stored session load side by side.
            async let lights: Void = WelcomeLightMetalRenderer.prepare()
            async let entitlements: Void = access.start()
            // The keyboard's first load stalls the main thread; take that
            // here, behind the still launch screen, not under the moving light.
            KeyboardWarmup.run()
            await appState.start()
            await lights
            isLightReady = true
            try? await Task.sleep(for: .seconds(1.5))
            stopsWaitingForAccess = true
            // The entrance loads its own sound; the rest wait until launch is done.
            SoundPlayer.shared.prepare()
            await entitlements
        }
        .onChange(of: appState.sessionState) { _, _ in
            // Session restoration can restore a profile from Supabase too.
            access.updateCompletion(savedCompletionDate)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await notifications.appBecameActive() }
            case .background:
                Task { await notifications.appWillResignActive() }
            default:
                break
            }
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
            access: access,
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
                onSignedIn: { session in
                    welcomeGeneration += 1
                    handleAuthenticatedSession(session)
                }
            )
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
        }
        // A deleted profile leaves nothing of the old screens behind.
        .id([appState.profileGeneration, welcomeGeneration])
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

    private struct NotificationAccountState: Equatable {
        let hasAccount: Bool
        let earlyAccessReminderAt: Date?
    }

    /// What the notification engine needs to know about the account.
    private var notificationAccountState: NotificationAccountState {
        let ledger = access.ledger
        let reminder = ledger.reminderEnabled && !access.hasPaidAccess ? ledger.reminderDate : nil
        return NotificationAccountState(
            hasAccount: appState.sessionState == .signedIn || appState.sessionState == .onboarding,
            earlyAccessReminderAt: reminder)
    }

    /// Where an unfinished questionnaire stopped, for the access screen.
    private var savedQuestionnaireProgress: Double? {
        guard let state = dependencies.profileCreationStore.load(),
              state.completedAt == nil, !state.isUnderageLocked else { return nil }
        return EarlyAccessView.questionnaireProgress(state.progress,
                                                     hasStartedEarlyAccess: access.ledger.effectiveStartedAt != nil)
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
