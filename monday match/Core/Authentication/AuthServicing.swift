import Foundation

enum RestoredSession {
    case signedOut
    case onboarding
    case signedIn
}

struct AppleAuthorizationPayload {
    let identityToken: String
    let rawNonce: String
    let fullName: PersonNameComponents?
}

protocol AuthServicing {
    func restoreSession() async throws -> RestoredSession
    func signInWithApple(
        payload: AppleAuthorizationPayload
    ) async throws -> RestoredSession
    func signOut() async throws
}

struct MockAuthService: AuthServicing {
    func restoreSession() async throws -> RestoredSession {
        return .signedOut
    }

    func signInWithApple(
        payload: AppleAuthorizationPayload
    ) async throws -> RestoredSession {
        try await Task.sleep(for: .milliseconds(450))
        return .onboarding
    }

    func signOut() async throws {
        // No-op in the Firebase-free development configuration.
    }
}
