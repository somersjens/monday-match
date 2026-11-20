import CloudKit
import CryptoKit
import Foundation

/// The profile as it is kept in the person's own iCloud: the answers and the
/// photos themselves.
struct ProfileBackupCopy: Equatable {
    var state: ProfileCreationState
    /// With the photos' bytes.
    var draft: ProfileDraft
}

/// Where the account's profile is backed up: the person's own iCloud.
@MainActor
protocol ProfileBackupStoring: AnyObject {
    /// False when no iCloud account is usable; nothing can be backed up then.
    func isAvailable() async throws -> Bool
    /// Nil when this account has no backup here (or iCloud is unavailable).
    func load(accountID: String) async throws -> ProfileBackupCopy?
    /// Saves the answers, the photos in `sending` and removes the photos in
    /// `removing`; photos in neither are already there.
    func save(_ copy: ProfileBackupCopy, accountID: String, sending: Set<UUID>, removing: Set<UUID>) async throws
    /// Succeeds when there is nothing to remove.
    func delete(accountID: String) async throws
}

/// Creating an account backs the profile up here, to the person's own iCloud,
/// never to our server: the server only receives a profile while it takes
/// part in automatic matching (202611200002_matching_only_profiles.sql).
/// Signing in on a new phone restores it from here.
///
/// iCloud is asked only when the profile changed since its last backup.
@MainActor
final class ProfileICloudBackup {
    private let store: ProfileBackupStoring
    private let defaults: UserDefaults

    /// Backups of deleted profiles that iCloud has not confirmed removing.
    nonisolated static let pendingDeletionsKey = "profileBackup.pendingDeletions.v1"
    nonisolated static let keyPrefix = "profileBackup.iCloud.v1."

    init(store: ProfileBackupStoring, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    /// What iCloud last confirmed for an account: a digest of the answers and
    /// of each photo.
    private struct Saved: Codable, Equatable {
        var content: Data
        var photos: [UUID: Data]
    }

    private func saved(_ accountID: String) -> Saved? {
        defaults.data(forKey: Self.keyPrefix + accountID).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
    }

    private func setSaved(_ value: Saved?, for accountID: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: Self.keyPrefix + accountID)
        } else {
            defaults.removeObject(forKey: Self.keyPrefix + accountID)
        }
    }

    private static func digest(state: ProfileCreationState, draft: ProfileDraft) -> Saved {
        var state = state
        // The questionnaire step last left open matters to no one.
        state.currentStep = .dateOfBirth
        var draft = draft
        let photos = Dictionary(draft.photos.map { ($0.id, Data(SHA256.hash(data: $0.imageData))) },
                                uniquingKeysWith: { first, _ in first })
        let order = draft.photos.map { [$0.id.uuidString, String($0.order)] }
        draft.photos = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var content = Data()
        content.append((try? encoder.encode(state)) ?? Data())
        content.append((try? encoder.encode(draft)) ?? Data())
        content.append((try? encoder.encode(order)) ?? Data())
        return Saved(content: Data(SHA256.hash(data: content)), photos: photos)
    }

    /// Backs up the profile when it changed. Without a usable iCloud account
    /// nothing happens.
    func save(state: ProfileCreationState, draft: ProfileDraft, accountID: String) async throws {
        let current = Self.digest(state: state, draft: draft)
        let previous = saved(accountID)
        guard current != previous else { return }
        guard try await store.isAvailable() else { return }
        let sending = Set(current.photos.filter { previous?.photos[$0.key] != $0.value }.keys)
        let removing = Set(previous?.photos.keys.filter { current.photos[$0] == nil } ?? [])
        try await store.save(ProfileBackupCopy(state: state, draft: draft), accountID: accountID,
                             sending: sending, removing: removing)
        setSaved(current, for: accountID)
    }

    func load(accountID: String) async throws -> ProfileBackupCopy? {
        try await store.load(accountID: accountID)
    }

    /// The phone now holds exactly what iCloud has.
    func markCurrent(_ copy: ProfileBackupCopy, accountID: String) {
        setSaved(Self.digest(state: copy.state, draft: copy.draft), for: accountID)
    }

    /// The profile was deleted: so is its backup, now or as soon as iCloud
    /// can be reached.
    func forget(accountID: String) async {
        setSaved(nil, for: accountID)
        pendingDeletions.insert(accountID)
        await retryPendingDeletions()
    }

    func retryPendingDeletions() async {
        for accountID in pendingDeletions.sorted() {
            guard (try? await store.delete(accountID: accountID)) != nil else { return }
            pendingDeletions.remove(accountID)
        }
    }

    private var pendingDeletions: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.pendingDeletionsKey) ?? []) }
        set {
            if newValue.isEmpty { defaults.removeObject(forKey: Self.pendingDeletionsKey) }
            else { defaults.set(newValue.sorted(), forKey: Self.pendingDeletionsKey) }
        }
    }
}

/// The profile in the private database of the app's iCloud container, the
/// same one the saved matches use. One `ProfileBackup` record per account
/// (named after the account) holds the answers; each photo is a
/// `ProfileBackupPhoto` record of its own ("<account>/<photo>"), so a record
/// never nears CloudKit's 1 MB limit. Every field is end-to-end encrypted.
///
/// Both record types have to be deployed to production in the CloudKit
/// Console before a TestFlight or App Store build can save.
@MainActor
final class CloudKitProfileBackupStore: ProfileBackupStoring {
    static let profileType = "ProfileBackup"
    static let photoType = "ProfileBackupPhoto"

    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }
    private let zoneID = CKRecordZone.ID(zoneName: "Profile", ownerName: CKCurrentUserDefaultName)
    private var hasZone = false

    /// The photos' order travels with the answers; their bytes do not.
    private struct PhotoEntry: Codable {
        let id: UUID
        let order: Int
    }

    init(container: CKContainer = CKContainer(identifier: CloudKitSavedMatchStore.containerIdentifier)) {
        self.container = container
    }

    func isAvailable() async throws -> Bool {
        try await container.accountStatus() == .available
    }

    func load(accountID: String) async throws -> ProfileBackupCopy? {
        guard try await isAvailable() else { return nil }
        let records = try await records(of: accountID)
        guard let profile = records.first(where: { $0.recordType == Self.profileType }),
              let stateData = profile.encryptedValues["state"] as? Data,
              let draftData = profile.encryptedValues["draft"] as? Data,
              let photoData = profile.encryptedValues["photos"] as? Data else { return nil }
        let state = try JSONDecoder().decode(ProfileCreationState.self, from: stateData)
        var draft = try JSONDecoder().decode(ProfileDraft.self, from: draftData)
        let entries = try JSONDecoder().decode([PhotoEntry].self, from: photoData)
        var bytes: [UUID: Data] = [:]
        for record in records where record.recordType == Self.photoType {
            if let id = UUID(uuidString: String(record.recordID.recordName.split(separator: "/").last ?? "")),
               let data = record.encryptedValues["photo"] as? Data {
                bytes[id] = data
            }
        }
        // A backup missing one of its photos is incomplete: nothing to restore.
        guard entries.allSatisfy({ bytes[$0.id] != nil }) else { return nil }
        draft.photos = entries.map { ProfilePhoto(id: $0.id, imageData: bytes[$0.id]!, order: $0.order) }
        return ProfileBackupCopy(state: state, draft: draft)
    }

    func save(_ copy: ProfileBackupCopy, accountID: String, sending: Set<UUID>, removing: Set<UUID>) async throws {
        if !hasZone {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
            hasZone = true
        }
        var draft = copy.draft
        let photos = draft.photos
        draft.photos = []
        let profile = CKRecord(recordType: Self.profileType, recordID: recordID(accountID))
        profile.encryptedValues["state"] = try JSONEncoder().encode(copy.state)
        profile.encryptedValues["draft"] = try JSONEncoder().encode(draft)
        profile.encryptedValues["photos"] = try JSONEncoder().encode(photos.map { PhotoEntry(id: $0.id, order: $0.order) })
        var saving = [profile]
        for photo in photos where sending.contains(photo.id) {
            let record = CKRecord(recordType: Self.photoType, recordID: recordID(accountID, photo: photo.id))
            record.encryptedValues["photo"] = photo.imageData
            saving.append(record)
        }
        // One atomic request: the answers never name a photo that is missing.
        let deleting = removing.map { recordID(accountID, photo: $0) }
        let (saved, deleted) = try await database.modifyRecords(saving: saving, deleting: deleting,
                                                                savePolicy: .allKeys, atomically: true)
        for result in saved.values { _ = try result.get() }
        for (_, result) in deleted {
            do { try result.get() } catch let error as CKError where error.code == .unknownItem {}
        }
    }

    func delete(accountID: String) async throws {
        guard try await isAvailable() else { return }
        let ids = try await records(of: accountID).map(\.recordID)
        guard !ids.isEmpty else { return }
        let (_, deleted) = try await database.modifyRecords(saving: [], deleting: ids)
        for (_, result) in deleted {
            do { try result.get() } catch let error as CKError where error.code == .unknownItem {}
        }
    }

    /// Every record of one account in the zone. The zone is small: one
    /// profile and its photos per account signed in with this iCloud.
    private func records(of accountID: String) async throws -> [CKRecord] {
        var found: [CKRecord] = []
        var token: CKServerChangeToken?
        var moreComing = true
        do {
            while moreComing {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                for (id, result) in changes.modificationResultsByID
                where id.recordName == accountID || id.recordName.hasPrefix(accountID + "/") {
                    if let record = try? result.get().record { found.append(record) }
                }
                token = changes.changeToken
                moreComing = changes.moreComing
            }
        } catch let error as CKError where error.code == .zoneNotFound {
            hasZone = false
            return []
        }
        hasZone = true
        return found
    }

    private func recordID(_ accountID: String, photo: UUID? = nil) -> CKRecord.ID {
        let name = photo.map { "\(accountID)/\($0.uuidString.lowercased())" } ?? accountID
        return CKRecord.ID(recordName: name, zoneID: zoneID)
    }
}
