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
/// The report is signed with an Apple App Attest key (`AppAttestPhotoReporter`),
/// so the server records it as coming from the genuine app on a genuine
/// iPhone. Since 20 November 2026 that is the only route: the server no longer
/// takes an unsigned report (202611200005), so a phone without App Attest (or
/// the simulator) cannot verify a photo. A failure is tried again on the next
/// sync; Android will report through Play Integrity.
@MainActor
final class DevicePhotoScanReporter: DevicePhotoReporting {
    private let client: SupabaseClient
    private let attestation: AttestedPhotoReporting?

    init(client: SupabaseClient, attestation: AttestedPhotoReporting? = nil) {
        self.client = client
        self.attestation = attestation ?? AppAttestPhotoReporter(client: client)
    }

    func reportPhotoScan(photoID: UUID) async throws {
        guard let attestation, attestation.isSupported else { throw AppAttestError.unsupported }
        do {
            try await attestation.reportPhotoScan(photoID: photoID)
        } catch AppAttestError.dailyLimit {
            throw PhotoVerificationServiceError.dailyLimit
        }
    }
}

nonisolated enum PhotoVerificationServiceError: Error, Equatable {
    case notRecorded, dailyLimit
}

/// Decoded off the main actor by Supabase, so these must not be main-actor isolated.
private nonisolated struct MatchingStatus: Decodable { let photo_verified: Bool }
