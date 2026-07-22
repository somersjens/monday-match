import Foundation

#if canImport(FirebaseAuth)
import FirebaseAuth

struct FirebaseAppleAuthService: AuthServicing {
    func restoreSession() async throws -> RestoredSession {
        guard Auth.auth().currentUser != nil else {
            return .signedOut
        }

        // A production implementation should query the profile document and
        // return `.onboarding` until the required profile fields are complete.
        return .signedIn
    }

    func signInWithApple(
        payload: AppleAuthorizationPayload
    ) async throws -> RestoredSession {
        let credential = OAuthProvider.appleCredential(
            withIDToken: payload.identityToken,
            rawNonce: payload.rawNonce,
            fullName: payload.fullName
        )

        _ = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<AuthDataResult, Error>) in

            Auth.auth().signIn(with: credential) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result else {
                    continuation.resume(
                        throwing: FirebaseAppleAuthError.missingAuthResult
                    )
                    return
                }

                continuation.resume(returning: result)
            }
        }

        return .onboarding
    }

    func signOut() async throws {
        try Auth.auth().signOut()
    }
}

enum FirebaseAppleAuthError: LocalizedError {
    case missingAuthResult

    var errorDescription: String? {
        "Firebase did not return an authentication result."
    }
}
#endif
