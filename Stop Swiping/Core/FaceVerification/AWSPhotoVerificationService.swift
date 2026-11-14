import FaceLiveness
import Foundation
import Supabase

/// Temporary streaming credentials are kept in memory for one scan. They cannot
/// create sessions, read results, compare faces, access Storage or attest success.
nonisolated struct AWSLivenessCredentials: Decodable, AWSTemporaryCredentials {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String
    private let expires: String
    var expiration: Date { Self.date(expires) ?? .distantPast }
    enum CodingKeys: String, CodingKey {
        case accessKeyId="access_key", secretAccessKey="secret_key", sessionToken="session_token", expires="expiration"
    }
    static func date(_ value: String) -> Date? {
        let formatter=ISO8601DateFormatter(); formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        return formatter.date(from:value) ?? ISO8601DateFormatter().date(from:value)
    }
}
nonisolated struct AWSLivenessCredentialProvider: AWSCredentialsProvider {
    let credentials: AWSLivenessCredentials
    func fetchAWSCredentials() async throws -> AWSCredentials {
        guard credentials.expiration > Date() else { throw AWSPhotoVerificationError.expired }
        return credentials
    }
}
nonisolated struct AWSPhotoVerificationSession: Decodable, Identifiable {
    let id: UUID
    let sessionID: String
    let region: String
    let credentials: AWSLivenessCredentials
    enum CodingKeys: String,CodingKey { case id="request_id",sessionID="session_id",region,credentials }
}
nonisolated enum AWSPhotoVerificationError: LocalizedError {
    case unavailable, expired, notVerified
    var errorDescription: String? {
        switch self {
        case .unavailable: "Server photo verification is not available yet. Please try again later."
        case .expired: "This verification expired. Please start a new check."
        case .notVerified: "The server could not verify this photo. Try a clear photo of yourself and repeat the scan."
        }
    }
}
/// Decoded off the main actor by Supabase, so these must not be main-actor isolated.
private nonisolated struct AWSMatchingStatus: Decodable { let photo_verified:Bool }
private nonisolated struct AWSVerificationResult: Decodable { let verified:Bool; let pending:Bool? }
@MainActor
final class AWSPhotoVerificationService {
    static let consentVersion="2026-11-14.aws.v1"
    private let client: SupabaseClient
    private let profileSync: ProfileCloudSyncing
    init(client: SupabaseClient, profileSync: ProfileCloudSyncing) { self.client=client; self.profileSync=profileSync }
    func start(photoID: UUID) async throws -> AWSPhotoVerificationSession {
        try await profileSync.synchronize()
        struct Body: Encodable { let action="start"; let photo_id:UUID; let consent_version=AWSPhotoVerificationService.consentVersion }
        do {
            let session: AWSPhotoVerificationSession = try await client.functions.invoke("aws-face-verification",
                options:FunctionInvokeOptions(body:Body(photo_id:photoID)))
            guard session.region=="eu-west-1", !session.sessionID.isEmpty else { throw AWSPhotoVerificationError.unavailable }
            return session
        } catch FunctionsError.httpError(let status,_) where status==503 || status==404 { throw AWSPhotoVerificationError.unavailable }
    }
    func photoIsVerified() async throws -> Bool {
        try await profileSync.synchronize()
        let result:AWSMatchingStatus=try await client.rpc("matching_status").execute().value
        return result.photo_verified
    }
    func complete(_ session: AWSPhotoVerificationSession) async throws {
        struct Body: Encodable { let action="complete"; let request_id:UUID }
        for _ in 0..<10 {
            let result: AWSVerificationResult = try await client.functions.invoke("aws-face-verification",
                options:FunctionInvokeOptions(body:Body(request_id:session.id)))
            if result.verified { return }
            guard result.pending==true else { throw AWSPhotoVerificationError.notVerified }
            try await Task.sleep(for:.seconds(1))
        }
        throw AWSPhotoVerificationError.expired
    }
}
