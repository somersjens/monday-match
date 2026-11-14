import FaceLiveness
import XCTest
@testable import Stop_Swiping

@MainActor
final class AWSPhotoVerificationTests: XCTestCase {
    func testStreamingCredentialsIncludeTokenAndExpire() async throws {
        let json=Data("""
        {"access_key":"fixture-access","secret_key":"fixture-secret","session_token":"fixture-session","expiration":"2000-01-01T00:00:00.000Z"}
        """.utf8)
        let credentials=try JSONDecoder().decode(AWSLivenessCredentials.self,from:json)
        XCTAssertEqual(credentials.sessionToken,"fixture-session")
        XCTAssertLessThan(credentials.expiration,Date())
        do { _=try await AWSLivenessCredentialProvider(credentials:credentials).fetchAWSCredentials(); XCTFail("Expired credentials must fail") }
        catch AWSPhotoVerificationError.expired {}
    }
    func testFractionalAndWholeSecondExpirationFormats() {
        XCTAssertNotNil(AWSLivenessCredentials.date("2080-01-01T00:00:00.000Z"))
        XCTAssertNotNil(AWSLivenessCredentials.date("2080-01-01T00:00:00Z"))
        XCTAssertNil(AWSLivenessCredentials.date("invalid"))
    }
}
