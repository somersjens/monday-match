import AuthenticationServices

/// Shows Apple's sign-in sheet from any button, so the app can draw its own
/// "Continue with Apple" control in the onboarding style.
@MainActor
final class AppleSignInPrompt: NSObject, ASAuthorizationControllerDelegate,
                               ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var controller: ASAuthorizationController?

    /// Throws `CancellationError` when the person closes Apple's sheet.
    func credential(hashedNonce: String) async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        MainActor.assumeIsolated {
            if let credential { finish(.success(credential)) }
            else { finish(.failure(AppleSignInError.invalidCredential)) }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        let canceled = (error as? ASAuthorizationError)?.code == .canceled
        MainActor.assumeIsolated {
            finish(.failure(canceled ? CancellationError() : error))
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { AppleSheetAnchor.current() }
    }

    private func finish(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}
