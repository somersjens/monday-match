import AuthenticationServices
import Combine
import XCTest
@testable import Stop_Swiping

@MainActor
final class SignInViewModelTests: XCTestCase {
    func testGoogleCompletesOnceAndPreventsConcurrentSignIn() async {
        let auth = TestSignInService()
        let model = SignInViewModel(authService: auth)
        let completed = expectation(description: "Authenticated")
        var callbacks = 0
        let onAuthenticated: (RestoredSession) -> Void = { result in
            guard case .signedIn = result else { return XCTFail("Unexpected session") }
            callbacks += 1
            completed.fulfill()
        }
        model.signInWithGoogle(onAuthenticated: onAuthenticated)
        model.signInWithGoogle(onAuthenticated: onAuthenticated)
        XCTAssertTrue(model.isSigningIn)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(auth.googleCalls, 1)
        XCTAssertEqual(callbacks, 1)
        XCTAssertFalse(model.isSigningIn)
        XCTAssertNil(model.errorMessage)
    }

    func testCancellationIsQuietAndUnlocksBothProviders() async {
        let auth = TestSignInService()
        auth.result = .failure(NSError(domain: ASWebAuthenticationSessionErrorDomain,
                                      code: ASWebAuthenticationSessionError.canceledLogin.rawValue))
        let model = SignInViewModel(authService: auth)
        let finished = expectation(description: "Cancelled")
        let observation = model.$isSigningIn.dropFirst().filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
        model.signInWithGoogle { _ in XCTFail("Cancelled sign-in cannot authenticate") }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isSigningIn)
        withExtendedLifetime(observation) {}
    }

    func testFailureShowsAnErrorAndAllowsRetry() async {
        let auth = TestSignInService()
        auth.result = .failure(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection failed"]))
        let model = SignInViewModel(authService: auth)
        let failed = expectation(description: "Failed")
        let observation = model.$isSigningIn.dropFirst().filter { !$0 }.prefix(1).sink { _ in failed.fulfill() }
        model.signInWithGoogle { _ in XCTFail("Failed sign-in cannot authenticate") }
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(model.errorMessage, "Connection failed")
        auth.result = .success(.signedIn)
        let retried = expectation(description: "Retried")
        model.signInWithGoogle { _ in retried.fulfill() }
        XCTAssertNil(model.errorMessage)
        await fulfillment(of: [retried], timeout: 2)
        XCTAssertEqual(auth.googleCalls, 2)
        withExtendedLifetime(observation) {}
    }
}

@MainActor
private final class TestSignInService: AuthServicing {
    var result: Result<RestoredSession, Error> = .success(.signedIn)
    var googleCalls = 0
    func restoreSession() async throws -> RestoredSession { .signedOut }
    func signInWithApple(payload: AppleAuthorizationPayload) async throws -> RestoredSession { try result.get() }
    func signInWithGoogle() async throws -> RestoredSession {
        googleCalls += 1
        await Task.yield()
        return try result.get()
    }
    func signOut() async throws {}
}
