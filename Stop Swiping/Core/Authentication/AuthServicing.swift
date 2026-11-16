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
    /// The session stored on this phone, without waiting for the network.
    /// Nil when only `restoreSession()` can tell.
    func localSession() -> RestoredSession?
    func restoreSession() async throws -> RestoredSession
    func signInWithApple(
        payload: AppleAuthorizationPayload
    ) async throws -> RestoredSession
    func signInWithGoogle() async throws -> RestoredSession
    func signOut() async throws
}

extension AuthServicing {
    func localSession() -> RestoredSession? { nil }
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
        // No-op in previews and tests. The app uses Supabase authentication.
    }

    func signInWithGoogle() async throws -> RestoredSession {
        try await Task.sleep(for: .milliseconds(450))
        return .onboarding
    }
}
