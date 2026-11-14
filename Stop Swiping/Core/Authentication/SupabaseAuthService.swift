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

    func restoreSession() async throws -> RestoredSession {
        do {
            _ = try await client.auth.session
        } catch AuthError.sessionMissing {
            return .signedOut
        }
        // A cloud outage must not destroy an otherwise valid local session.
        try? await profileSync.restoreIfNeeded()
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
        try await profileSync.connectAccount()
        return profileSync.hasCompletedProfile ? .signedIn : .onboarding
    }

    func signOut() async throws {
        try await client.auth.signOut(scope: .local)
    }
}
