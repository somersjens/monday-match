import CryptoKit
import DeviceCheck
import Foundation
import Supabase

/// Signs photo-scan reports with an Apple App Attest key, so the server
/// knows they come from this genuine app on a genuine iPhone and not from a
/// modified client (`app-attest` edge function). Android does the same with
/// Play Integrity.
///
/// The key lives in the Secure Enclave; only its ID is stored here. It is
/// certified by Apple once per account, then every report is signed with it.
@MainActor
protocol AttestedPhotoReporting {
    /// False on the simulator and on devices without App Attest.
    var isSupported: Bool { get }
    func reportPhotoScan(photoID: UUID) async throws
}

nonisolated enum AppAttestError: Error, Equatable {
    case unsupported, dailyLimit, rejected, unavailable
}

@MainActor
final class AppAttestPhotoReporter: AttestedPhotoReporting {
    private let client: SupabaseClient
    private let defaults: UserDefaults
    private let service = DCAppAttestService.shared
    private static let keyIDKey = "appAttest.keyID.v1"
    private static let registeredKey = "appAttest.registeredFor.v1"

    init(client: SupabaseClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    var isSupported: Bool { service.isSupported }

    func reportPhotoScan(photoID: UUID) async throws {
        guard isSupported else { throw AppAttestError.unsupported }
        let user = try await client.auth.session.user.id.uuidString.lowercased()
        var keyID = try await ensureKey()
        if defaults.string(forKey: Self.registeredKey) != "\(user)|\(keyID)" {
            do {
                try await register(keyID: keyID)
            } catch DCError.invalidKey {
                // The key was lost (restore to another phone, app reinstall): make a new one.
                defaults.removeObject(forKey: Self.keyIDKey)
                keyID = try await ensureKey()
                try await register(keyID: keyID)
            }
            defaults.set("\(user)|\(keyID)", forKey: Self.registeredKey)
        }

        let challenge = try await issueChallenge()
        let clientData = try Self.clientData(challenge: challenge.challenge, photoID: photoID)
        let assertion = try await service.generateAssertion(keyID, clientDataHash: Data(SHA256.hash(data: clientData)))
        do {
            try await invoke(Body(action: "photo", challengeId: challenge.id, keyId: keyID,
                                  assertion: assertion.base64EncodedString(), clientData: clientData.base64EncodedString(),
                                  photoId: photoID.uuidString.lowercased()))
        } catch AppAttestError.rejected where defaults.string(forKey: Self.registeredKey) != nil {
            // The server no longer knows the key: register it again next time.
            defaults.removeObject(forKey: Self.registeredKey)
            throw AppAttestError.rejected
        }
    }

    /// The exact bytes the key signs; the server checks every field.
    nonisolated static func clientData(challenge: String, photoID: UUID) throws -> Data {
        struct Signed: Encodable { let challenge: String; let photo_id: String; let purpose: String }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(Signed(challenge: challenge, photo_id: photoID.uuidString.lowercased(),
                                         purpose: "photo_verification"))
    }

    private func ensureKey() async throws -> String {
        if let keyID = defaults.string(forKey: Self.keyIDKey) { return keyID }
        let keyID = try await service.generateKey()
        defaults.set(keyID, forKey: Self.keyIDKey)
        return keyID
    }

    private func register(keyID: String) async throws {
        let challenge = try await issueChallenge()
        guard let bytes = Data(base64Encoded: challenge.challenge) else { throw AppAttestError.unavailable }
        let attestation = try await service.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: bytes)))
        try await invoke(Body(action: "register", challengeId: challenge.id, keyId: keyID,
                              attestation: attestation.base64EncodedString()))
    }

    private nonisolated struct Challenge: Decodable { let id: String; let challenge: String }
    private nonisolated struct Body: Encodable {
        let action: String
        var challengeId: String? = nil
        var keyId: String? = nil
        var attestation: String? = nil
        var assertion: String? = nil
        var clientData: String? = nil
        var photoId: String? = nil
    }

    private func issueChallenge() async throws -> Challenge {
        do {
            return try await client.functions.invoke("app-attest", options: FunctionInvokeOptions(body: Body(action: "challenge")))
        } catch {
            throw Self.mapped(error)
        }
    }

    private func invoke(_ body: Body) async throws {
        do {
            try await client.functions.invoke("app-attest", options: FunctionInvokeOptions(body: body))
        } catch {
            throw Self.mapped(error)
        }
    }

    private nonisolated static func mapped(_ error: Error) -> Error {
        guard case FunctionsError.httpError(let code, let data) = error else { return AppAttestError.unavailable }
        let message = String(decoding: data, as: UTF8.self)
        if code == 429, message.contains("daily_limit") { return AppAttestError.dailyLimit }
        if code == 403 || code == 409 { return AppAttestError.rejected }
        return AppAttestError.unavailable
    }
}
