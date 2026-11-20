import Foundation
import Supabase

struct SupabaseAuthService: AuthServicing {
    typealias OAuthFlow = @MainActor @Sendable (URL) async throws -> URL

    let client: SupabaseClient
    let profileSync: SupabaseProfileSync
    private let oauthFlow: OAuthFlow?

    init(client: SupabaseClient, profileSync: SupabaseProfileSync, oauthFlow: OAuthFlow? = nil) {
        self.client = client
        self.profileSync = profileSync
        self.oauthFlow = oauthFlow
    }

    /// The Keychain's session, possibly expired. Reading it needs no network,
    /// so the app can open on it at once while `restoreSession()` refreshes.
    func localSession() -> RestoredSession? {
        guard let session = client.auth.currentSession else { return .signedOut }
        guard profileSync.hasCompletedProfile else { return .onboarding }
        // A finished profile the account never chose (signing in stopped at
        // the choice): only the server can tell whether it may stay.
        return profileSync.ownsProfile(userID: session.user.id) ? .signedIn : nil
    }

    func restoreSession() async throws -> RestoredSession {
        do {
            _ = try await client.auth.session
        } catch AuthError.sessionMissing {
            return .signedOut
        } catch {
            // Offline, a server outage (5xx/429) or a cancelled refresh: the
            // stored session stays valid until the server says otherwise. When
            // the server does reject the token, the SDK has already removed
            // the stored session, so this reads as signed out.
            return localSession() ?? .signedOut
        }
        // A cloud outage must not destroy an otherwise valid local session.
        if (try? await profileSync.restoreIfNeeded()) == false {
            // Signing in stopped before the person chose between the account's
            // profile and the new answers. Signed out, the account card offers
            // signing in again, which asks once more; the answers stay.
            try? await client.auth.signOut(scope: .local)
            return .signedOut
        }
        return profileSync.hasCompletedProfile ? .signedIn : .onboarding
    }

    func signInWithApple(payload: AppleAuthorizationPayload) async throws -> RestoredSession {
        _ = try await client.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(
            provider: .apple, idToken: payload.identityToken, nonce: payload.rawNonce
        ))
        return try await finishSignIn()
    }

    func signInWithGoogle() async throws -> RestoredSession {
        if let oauthFlow {
            _ = try await client.auth.signInWithOAuth(
                provider: .google, redirectTo: SupabaseConfiguration.authRedirectURL,
                queryParams: [("prompt", "select_account")], launchFlow: oauthFlow
            )
        } else {
            // The SDK presents the system authentication browser and exchanges
            // the callback's authorization code using PKCE.
            _ = try await client.auth.signInWithOAuth(
                provider: .google, redirectTo: SupabaseConfiguration.authRedirectURL,
                queryParams: [("prompt", "select_account")]
            )
        }
        return try await finishSignIn()
    }

    private func finishSignIn() async throws -> RestoredSession {
        // Keep the account step open on failure so the same account can
        // retry saving the profile before progressing to notifications.
        // AccountProfileChoiceRequired reaches the sign-in screen, which asks.
        try await profileSync.connectAccount()
        return profileSync.hasCompletedProfile ? .signedIn : .onboarding
    }

    func keepNewAnswers() async throws -> RestoredSession {
        try await profileSync.keepNewAnswers()
        return profileSync.hasCompletedProfile ? .signedIn : .onboarding
    }

    func restoreAccountProfile() async throws -> RestoredSession {
        try await profileSync.restoreAccountProfile()
        return profileSync.hasCompletedProfile ? .signedIn : .onboarding
    }

    func signOut() async throws {
        try await client.auth.signOut(scope: .local)
    }
}
