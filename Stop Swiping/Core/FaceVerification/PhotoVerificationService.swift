import Foundation
import Supabase

/// Tells the server that this phone's own live scan matched the selected
/// photo, so matching treats that photo version as verified. The scan, its
/// frames and face features never leave the phone: only the photo ID is sent.
///
/// The server takes the app's word for the result. That is the beta's
/// trade-off; the AWS check that proves it on the server is parked in
/// `archive/aws-face-liveness` (see docs/aws-photo-verification.md).
@MainActor
final class PhotoVerificationService {
    private let client: SupabaseClient
    private let profileSync: ProfileCloudSyncing

    init(client: SupabaseClient, profileSync: ProfileCloudSyncing) {
        self.client = client
        self.profileSync = profileSync
    }

    /// Whether the server already has this account's current matching photo
    /// as verified, for example after a reinstall.
    func photoIsVerified() async throws -> Bool {
        try await profileSync.synchronize()
        let status: MatchingStatus = try await client.rpc("matching_status").execute().value
        return status.photo_verified
    }

    /// Uploads the profile and photo first: the server records the exact
    /// stored version of the selected photo, so replacing it undoes this.
    func recordDeviceScan(photoID: UUID) async throws {
        try await profileSync.synchronize()
        let recorded: Bool = try await client
            .rpc("record_device_photo_verification", params: Params(p_photo_id: photoID))
            .execute().value
        guard recorded else { throw PhotoVerificationServiceError.notRecorded }
    }
}

nonisolated enum PhotoVerificationServiceError: Error {
    case notRecorded
}

/// Decoded off the main actor by Supabase, so these must not be main-actor isolated.
private nonisolated struct MatchingStatus: Decodable { let photo_verified: Bool }
private nonisolated struct Params: Encodable { let p_photo_id: UUID }
