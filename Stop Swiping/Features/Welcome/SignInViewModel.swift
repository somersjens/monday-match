import AuthenticationServices
import Combine
import Foundation

@MainActor
final class SignInViewModel: ObservableObject {
    enum Provider: Equatable {
        case apple
        case google
    }

    /// The provider whose sheet or request is in progress.
    @Published private(set) var activeProvider: Provider?
    @Published var errorMessage: String?

    var isSigningIn: Bool { activeProvider != nil }

    private let authService: AuthServicing
    private let nonceGenerator = NonceGenerator()

    init(authService: AuthServicing) {
        self.authService = authService
    }

    func signInWithApple(onAuthenticated: @escaping (RestoredSession) -> Void) {
        start(.apple, onAuthenticated: onAuthenticated) { [authService, nonceGenerator] in
            let nonce = try nonceGenerator.randomNonce()
            let credential = try await AppleSignInPrompt().credential(hashedNonce: nonceGenerator.sha256(nonce))
            guard let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                throw AppleSignInError.invalidCredential
            }
            return try await authService.signInWithApple(
                payload: AppleAuthorizationPayload(identityToken: token, rawNonce: nonce,
                                                   fullName: credential.fullName)
            )
        }
    }

    func signInWithGoogle(onAuthenticated: @escaping (RestoredSession) -> Void) {
        start(.google, onAuthenticated: onAuthenticated) { [authService] in
            try await authService.signInWithGoogle()
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func start(_ provider: Provider, onAuthenticated: @escaping (RestoredSession) -> Void,
                       signIn: @escaping @MainActor () async throws -> RestoredSession) {
        guard activeProvider == nil else { return }
        errorMessage = nil
        activeProvider = provider
        Task {
            do {
                let session = try await signIn()
                activeProvider = nil
                onAuthenticated(session)
            } catch {
                handleSignInError(error)
                activeProvider = nil
            }
        }
    }

    private func handleSignInError(_ error: Error) {
        // Closing either provider's system sheet is a normal cancellation.
        if error is CancellationError { return }
        if let error = error as? ASAuthorizationError, error.code == .canceled { return }
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin { return }
        errorMessage = error.localizedDescription
    }
}

enum AppleSignInError: LocalizedError {
    case invalidCredential

    var errorDescription: String? {
        L10n("Apple did not return a usable identity credential.")
    }
}
