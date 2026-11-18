import Foundation

/// Photos that came with a phone-to-phone exchange, one file per match. A
/// photo lives as long as its match: deleting the match deletes it.
nonisolated struct MatchPhotoStore: Sendable {
    static let shared = MatchPhotoStore()

    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "MatchPhotos", directoryHint: .isDirectory)
    }

    func save(_ data: Data, for id: UUID) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(for: id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func photo(for id: UUID) -> Data? {
        try? Data(contentsOf: url(for: id))
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// Removes every photo whose match is gone.
    func prune(keeping ids: Set<UUID>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let kept = Set(ids.map { url(for: $0).lastPathComponent })
        for file in files where !kept.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(for id: UUID) -> URL {
        directory.appending(path: id.uuidString.lowercased() + ".jpg")
    }
}
