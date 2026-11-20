import CloudKit
import Foundation

/// A saved match as it is kept in the person's own iCloud.
struct CloudSavedMatch: Equatable {
    let snapshot: MatchSnapshot
    /// The photo that came with the exchange.
    let photo: Data?

    var id: UUID { snapshot.id }
}

/// Where the saved matches are backed up: the person's own iCloud.
@MainActor
protocol SavedMatchCloudStoring: AnyObject {
    /// Who the backup belongs to, or nil when no iCloud account is usable.
    func accountID() async throws -> String?
    func fetchAll() async throws -> [CloudSavedMatch]
    func save(_ match: CloudSavedMatch) async throws
    /// Succeeds when the match is already gone.
    func delete(_ id: UUID) async throws
    /// Removes every saved match. Succeeds when there is nothing to remove.
    func deleteAll() async throws
}

/// Backs up the matches kept under My matches (phone to phone, QR, and the
/// server matches someone talked in) to the person's own iCloud, so a new
/// phone or a reinstall brings them back without them ever reaching our
/// server. Demo matches stay on the phone.
///
/// iCloud is asked only when something changed, when a profile was deleted,
/// or once to merge this phone with the backup.
@MainActor
final class SavedMatchCloudBackup {
    /// Survives the deletion of every saved match: set until iCloud confirms
    /// the backup is gone too.
    nonisolated static let wipeKey = "savedMatchCloud.wipe.v1"

    private let store: SavedMatchCloudStoring
    private let defaults: UserDefaults
    private let photos: MatchPhotoStore
    private let notifications: NotificationCenter
    private var changeObserver: NSObjectProtocol?
    private var worker: Task<Void, Never>?
    private var needsAnotherPass = false

    init(store: SavedMatchCloudStoring, defaults: UserDefaults = .standard, photos: MatchPhotoStore = .shared,
         notifications: NotificationCenter = .default) {
        self.store = store
        self.defaults = defaults
        self.photos = photos
        self.notifications = notifications
        changeObserver = notifications.addObserver(forName: .savedMatchesChanged, object: defaults,
                                                   queue: nil) { [weak self] note in
            let ids = note.userInfo?[SavedMatchStore.changedIDsKey] as? [UUID] ?? []
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pending.formUnion(ids)
                Task { await self.sync() }
            }
        }
    }

    deinit {
        if let changeObserver { notifications.removeObserver(changeObserver) }
    }

    /// Matches changed on this phone and not yet in iCloud: a saved, renamed
    /// or broken one is sent, a deleted one removed.
    private(set) var pending: Set<UUID> {
        get { Set(defaults.stringArray(forKey: SavedMatchStore.backupPendingKey)?.compactMap(UUID.init) ?? []) }
        set {
            if newValue.isEmpty { defaults.removeObject(forKey: SavedMatchStore.backupPendingKey) }
            else { defaults.set(newValue.map(\.uuidString), forKey: SavedMatchStore.backupPendingKey) }
        }
    }

    /// The iCloud account whose backup this phone has merged with.
    private var mergedAccount: String? {
        get { defaults.string(forKey: SavedMatchStore.backupMergedKey) }
        set { defaults.set(newValue, forKey: SavedMatchStore.backupMergedKey) }
    }

    private var needsWipe: Bool {
        get { defaults.bool(forKey: Self.wipeKey) }
        set { defaults.set(newValue, forKey: Self.wipeKey) }
    }

    /// The profile was deleted: so is its backup, now or as soon as iCloud
    /// can be reached. Nothing is merged back before that.
    func wipe() {
        needsWipe = true
        mergedAccount = nil
        Task { await sync() }
    }

    /// Runs at launch and after every change. Failures wait for the next one.
    func sync() async {
        needsAnotherPass = true
        if let worker { await worker.value; return }
        let task = Task {
            while needsAnotherPass {
                needsAnotherPass = false
                await syncOnce()
            }
        }
        worker = task
        await task.value
        worker = nil
    }

    private func syncOnce() async {
        // Nothing changed, and the backup was merged before: no need to ask.
        guard needsWipe || !pending.isEmpty || mergedAccount == nil else { return }
        if needsWipe {
            guard (try? await store.deleteAll()) != nil else { return }
            needsWipe = false
        }
        guard let accountID = try? await store.accountID() else { return }
        if mergedAccount != accountID {
            guard (try? await merge()) != nil else { return }
            mergedAccount = accountID
        }
        await sendPending()
    }

    /// The backup's matches join the phone's, and the phone's own go to the
    /// backup. A match deleted here but not yet in iCloud stays deleted.
    private func merge() async throws {
        let backedUp = try await store.fetchAll()
        var local = SavedMatchStore.stored(defaults: defaults)
        let localIDs = Set(local.map(\.id))
        let waiting = pending
        let added = backedUp.filter { !localIDs.contains($0.id) && !waiting.contains($0.id) }
        for match in added {
            local.append(match.snapshot)
            if let photo = match.photo { photos.save(photo, for: match.id) }
        }
        if !added.isEmpty {
            SavedMatchStore.store(local, defaults: defaults)
            notifications.post(name: .savedMatchesRestored, object: defaults)
        }
        let inBackup = Set(backedUp.map(\.id))
        pending.formUnion(local.filter { !$0.isDemo && !inBackup.contains($0.id) }.map(\.id))
    }

    private func sendPending() async {
        let local = SavedMatchStore.stored(defaults: defaults)
        for id in pending.sorted(by: { $0.uuidString < $1.uuidString }) {
            do {
                let match = local.first { $0.id == id }
                if match?.isDemo == true {
                    // Demos never leave the phone.
                } else if let match {
                    try await store.save(CloudSavedMatch(snapshot: match, photo: photos.photo(for: id)))
                } else {
                    try await store.delete(id)
                }
                pending.remove(id)
            } catch {
                return
            }
        }
    }
}

/// The saved matches in the private database of the app's iCloud container:
/// the person's own iCloud, which counts against their storage. Each match is
/// one record whose fields are end-to-end encrypted, so neither Apple nor we
/// can read them.
///
/// The record type is created in the development environment on first use;
/// it has to be deployed to production in the CloudKit Console before a
/// TestFlight or App Store build can save.
@MainActor
final class CloudKitSavedMatchStore: SavedMatchCloudStoring {
    nonisolated static let containerIdentifier = "iCloud.Hakketjak.monday-match"
    static let recordType = "SavedMatch"

    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }
    /// A zone of its own: it can be read without query indexes and removed
    /// in one step.
    private let zoneID = CKRecordZone.ID(zoneName: "SavedMatches", ownerName: CKCurrentUserDefaultName)
    private var hasZone = false

    init(container: CKContainer = CKContainer(identifier: CloudKitSavedMatchStore.containerIdentifier)) {
        self.container = container
    }

    func accountID() async throws -> String? {
        guard try await container.accountStatus() == .available else { return nil }
        return try await container.userRecordID().recordName
    }

    func fetchAll() async throws -> [CloudSavedMatch] {
        var matches: [CloudSavedMatch] = []
        var token: CKServerChangeToken?
        var moreComing = true
        do {
            while moreComing {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                for (_, result) in changes.modificationResultsByID {
                    if let match = try? Self.match(from: result.get().record) { matches.append(match) }
                }
                token = changes.changeToken
                moreComing = changes.moreComing
            }
        } catch let error as CKError where error.code == .zoneNotFound {
            return []
        }
        hasZone = true
        return matches
    }

    func save(_ match: CloudSavedMatch) async throws {
        if !hasZone {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
            hasZone = true
        }
        let record = CKRecord(recordType: Self.recordType, recordID: recordID(match.id))
        record.encryptedValues["snapshot"] = try JSONEncoder().encode(match.snapshot)
        record.encryptedValues["photo"] = match.photo
        // The phone's copy replaces whatever iCloud holds for this match.
        let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        _ = try saved[record.recordID]?.get()
    }

    func delete(_ id: UUID) async throws {
        do {
            let (_, deleted) = try await database.modifyRecords(saving: [], deleting: [recordID(id)])
            try deleted[recordID(id)]?.get()
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // Already gone.
        }
    }

    func deleteAll() async throws {
        do {
            _ = try await database.deleteRecordZone(withID: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound {
            // Nothing was backed up.
        }
        hasZone = false
    }

    private func recordID(_ id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString.lowercased(), zoneID: zoneID)
    }

    private static func match(from record: CKRecord) throws -> CloudSavedMatch {
        guard let data = record.encryptedValues["snapshot"] as? Data else { throw CKError(.unknownItem) }
        return CloudSavedMatch(snapshot: try JSONDecoder().decode(MatchSnapshot.self, from: data),
                               photo: record.encryptedValues["photo"] as? Data)
    }
}
