import Foundation
import Supabase

/// The matching photo is verified by a live scan on this phone; the scan,
/// its frames and face features never leave it. The phone remembers that the
/// photo passed. The server only hears of it once the photo is uploaded with
/// a profile in automatic matching (`SupabaseProfileSync` then calls
/// `DevicePhotoScanReporter`), and again after switching matching back on,
/// because the server removes the photo whenever matching goes off.
@MainActor
final class PhotoVerificationService {
    private let client: SupabaseClient
    private let profileSync: ProfileCloudSyncing

    init(client: SupabaseClient, profileSync: ProfileCloudSyncing) {
        self.client = client
        self.profileSync = profileSync
    }

    /// Whether the server already has this account's current matching photo
    /// as verified, for example after a reinstall. Only a profile in
    /// automatic matching is on the server; without one there is nothing to ask.
    func photoIsVerified() async throws -> Bool {
        guard profileSync.hasMatchingProfileOnServer else { return false }
        let status: MatchingStatus = try await client.rpc("matching_status").execute().value
        return status.photo_verified
    }
}

/// Tells the server that this phone's own live scan matched the stored
/// matching photo, so matching treats that photo version as verified. Only
/// the photo ID is sent.
///
/// Where the device supports it, the report is signed with an Apple App
/// Attest key (`AppAttestPhotoReporter`), so the server records it as coming
/// from the genuine app. Elsewhere (the simulator, or while the attest
/// function isn't deployed) the server still takes the app's word for it;
/// see supabase/migrations/202611190012_app_attest.sql for switching that off.
@MainActor
final class DevicePhotoScanReporter: DevicePhotoReporting {
    private let client: SupabaseClient
    private let attestation: AttestedPhotoReporting?

    init(client: SupabaseClient, attestation: AttestedPhotoReporting? = nil) {
        self.client = client
        self.attestation = attestation ?? AppAttestPhotoReporter(client: client)
    }

    func reportPhotoScan(photoID: UUID) async throws {
        if let attestation, attestation.isSupported {
            do {
                try await attestation.reportPhotoScan(photoID: photoID)
                return
            } catch AppAttestError.dailyLimit {
                throw PhotoVerificationServiceError.dailyLimit
            } catch {
                // Not deployed yet, a network error, or an attest failure:
                // the unproven route below still works until it is revoked.
            }
        }
        let recorded: Bool = try await client
            .rpc("record_device_photo_verification", params: Params(p_photo_id: photoID))
            .execute().value
        guard recorded else { throw PhotoVerificationServiceError.notRecorded }
    }
}

nonisolated enum PhotoVerificationServiceError: Error, Equatable {
    case notRecorded, dailyLimit
}

/// Decoded off the main actor by Supabase, so these must not be main-actor isolated.
private nonisolated struct MatchingStatus: Decodable { let photo_verified: Bool }
private nonisolated struct Params: Encodable { let p_photo_id: UUID }
