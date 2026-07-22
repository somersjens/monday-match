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

    private let authService: AuthServicing

    init(authService: AuthServicing) {
        self.authService = authService
    }

    func start() async {
        do {
            let session = try await authService.restoreSession()

            switch session {
            case .signedOut:
                sessionState = .signedOut
            case .onboarding:
                sessionState = .onboarding
            case .signedIn:
                sessionState = .signedIn
            }
        } catch {
            sessionState = .signedOut
        }
    }

    func showOnboarding() {
        sessionState = .onboarding
        navigationPath.removeAll()
    }

    func showSignedInApp() {
        sessionState = .signedIn
        navigationPath.removeAll()
    }

    func signOut() async {
        do {
            try await authService.signOut()
        } catch {
            // Logging and user-facing error handling will be added later.
        }

        sessionState = .signedOut
        navigationPath.removeAll()
    }
}
