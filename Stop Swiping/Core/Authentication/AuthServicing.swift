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

/// Signing in found a profile saved on the account while this phone holds a
/// newly finished one. The person chooses which one the account keeps, with
/// `keepNewAnswers()` or `restoreAccountProfile()`; until then nothing is
/// sent and nothing on the phone changes.
struct AccountProfileChoiceRequired: Error {}

protocol AuthServicing {
    /// The session stored on this phone, without waiting for the network.
    /// Nil when only `restoreSession()` can tell.
    func localSession() -> RestoredSession?
    func restoreSession() async throws -> RestoredSession
    func signInWithApple(
        payload: AppleAuthorizationPayload
    ) async throws -> RestoredSession
    func signInWithGoogle() async throws -> RestoredSession
    /// After `AccountProfileChoiceRequired`: the phone's new answers replace
    /// the account's saved profile.
    func keepNewAnswers() async throws -> RestoredSession
    /// After `AccountProfileChoiceRequired`: the account's saved profile
    /// replaces the phone's new answers.
    func restoreAccountProfile() async throws -> RestoredSession
    func signOut() async throws
}

extension AuthServicing {
    func localSession() -> RestoredSession? { nil }
    func keepNewAnswers() async throws -> RestoredSession { throw SupabaseSetupError.unavailable }
    func restoreAccountProfile() async throws -> RestoredSession { throw SupabaseSetupError.unavailable }
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
