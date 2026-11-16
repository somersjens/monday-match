import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    enum SessionState: Equatable {
        case loading
        case signedOut
        case onboarding
        case signedIn
    }

    @Published private(set) var sessionState: SessionState = .loading
    @Published var navigationPath: [AppRoute] = []
    /// Changes when the profile is deleted, so every screen starts over.
    @Published private(set) var profileGeneration = 0

    private let authService: AuthServicing

    init(authService: AuthServicing) {
        self.authService = authService
    }

    /// Counts the transitions people make themselves, so a session check
    /// that finishes late never undoes one.
    private var transitions = 0
    /// How long a reinstalled phone may restore its profile from the account
    /// before the questionnaire shows instead.
    var restoreGracePeriod: Duration = .seconds(3)

    /// Opens on the session stored on this phone straight away. The network
    /// check (refreshing the token, restoring a profile) keeps running after
    /// this returns and only changes the screen when it learns something new.
    func start() async {
        let startedAt = transitions
        let verification = Task { await verifiedState() }
        switch authService.localSession() {
        case .signedOut?:
            sessionState = .signedOut
        case .signedIn?:
            sessionState = .signedIn
        case .onboarding?:
            // Usually a reinstall: the account still has its profile. Give it
            // a moment to come back before showing the questionnaire.
            let restored = await withTaskGroup(of: SessionState?.self) { group in
                group.addTask { await verification.value }
                group.addTask { [restoreGracePeriod] in
                    try? await Task.sleep(for: restoreGracePeriod)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            sessionState = restored ?? .onboarding
        case nil:
            sessionState = await verification.value
            return
        }
        Task {
            let verified = await verification.value
            guard transitions == startedAt, verified != sessionState else { return }
            sessionState = verified
        }
    }

    private func verifiedState() async -> SessionState {
        do {
            switch try await authService.restoreSession() {
            case .signedOut: return .signedOut
            case .onboarding: return .onboarding
            case .signedIn: return .signedIn
            }
        } catch {
            return .signedOut
        }
    }

    func showOnboarding() {
        transitions += 1
        sessionState = .onboarding
        navigationPath.removeAll()
    }

    func showSignedInApp() {
        transitions += 1
        sessionState = .signedIn
        navigationPath.removeAll()
    }

    /// The profile is gone from the phone and the server: back to the first
    /// welcome screen, as on a fresh install.
    func showWelcomeAfterProfileDeletion() {
        transitions += 1
        sessionState = .signedOut
        navigationPath.removeAll()
        profileGeneration += 1
    }

    /// Runs while the session still exists, so the server can forget this
    /// phone's push registration before the account is gone from it.
    var willSignOut: (() async -> Void)?

    func signOut() async {
        transitions += 1
        await willSignOut?()
        do {
            try await authService.signOut()
        } catch {
            // Logging and user-facing error handling will be added later.
        }

        sessionState = .signedOut
        navigationPath.removeAll()
    }
}
