import Foundation
import Supabase

struct SupabaseConfiguration {
    static let authRedirectURL = URL(string: "stopswiping://auth/callback")!
    let url: URL
    let publishableKey: String

    init?(values: [String: Any]) {
        guard let address = values["SUPABASE_URL"] as? String,
              let url = URL(string: address), url.scheme == "https", url.host != nil,
              let key = values["SUPABASE_PUBLISHABLE_KEY"] as? String,
              key.hasPrefix("sb_publishable_") else { return nil }
        self.url = url
        publishableKey = key
    }

    static var bundled: Self? { Self(values: Bundle.main.infoDictionary ?? [:]) }

    func makeClient() -> SupabaseClient {
        // Opts in to the next major release's behaviour: the stored session is
        // emitted as-is, even when expired. Only the client's own listener
        // observes it, and it picks up the refreshed token right after.
        SupabaseClient(
            supabaseURL: url,
            supabaseKey: publishableKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }
}

enum SupabaseSetupError: LocalizedError {
    case unavailable
    case wrongAccount

    var errorDescription: String? {
        switch self {
        case .unavailable: L10n("Account creation is temporarily unavailable. Please try again later.")
        case .wrongAccount: L10n("Please sign in again to sync your profile.")
        }
    }
}

/// Missing configuration must never silently create a mock account.
struct UnconfiguredSupabaseAuthService: AuthServicing {
    func restoreSession() async throws -> RestoredSession { .signedOut }
    func signInWithApple(payload: AppleAuthorizationPayload) async throws -> RestoredSession {
        throw SupabaseSetupError.unavailable
    }
    func signInWithGoogle() async throws -> RestoredSession {
        throw SupabaseSetupError.unavailable
    }
    func signOut() async throws {}
}
