import AuthenticationServices
import Combine
import Foundation

@MainActor
final class AppleSignInViewModel: ObservableObject {
    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?

    private let authService: AuthServicing
    private let nonceGenerator = NonceGenerator()
    private var currentNonce: String?

    init(authService: AuthServicing) {
        self.authService = authService
    }

    func configure(
        request: ASAuthorizationAppleIDRequest
    ) {
        do {
            let nonce = try nonceGenerator.randomNonce()
            currentNonce = nonce

            request.requestedScopes = [
                .fullName,
                .email
            ]
            request.nonce = nonceGenerator.sha256(nonce)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handle(
        result: Result<ASAuthorization, Error>,
        onAuthenticated: @escaping (RestoredSession) -> Void
    ) {
        Task {
            isSigningIn = true
            defer { isSigningIn = false }

            do {
                let authorization = try result.get()

                guard
                    let credential = authorization.credential
                        as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let token = String(
                        data: tokenData,
                        encoding: .utf8
                    ),
                    let nonce = currentNonce
                else {
                    throw AppleSignInError.invalidCredential
                }

                let session = try await authService.signInWithApple(
                    payload: AppleAuthorizationPayload(
                        identityToken: token,
                        rawNonce: nonce,
                        fullName: credential.fullName
                    )
                )

                onAuthenticated(session)
            } catch {
                errorMessage = error.localizedDescription
            }

            currentNonce = nil
        }
    }
}

enum AppleSignInError: LocalizedError {
    case invalidCredential

    var errorDescription: String? {
        L10n("Apple did not return a usable identity credential.")
    }
}
