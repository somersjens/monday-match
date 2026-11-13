import Foundation

enum ProfileRepositoryError: LocalizedError {
    case documentsDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            return L10n("The app's local storage directory is unavailable.")
        }
    }
}

/// One shared repository owns the file for the lifetime of the app. Keep its
/// decoded value in memory so view reads do not repeatedly decode photo data.
final class FileProfileRepository: ProfileRepository {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    private var cachedProfile: ProfileDraft?
    private var hasLoadedProfile = false

    init(
        fileManager: FileManager = .default,
        filename: String = "profile.json"
    ) throws {
        self.fileManager = fileManager

        guard let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw ProfileRepositoryError.documentsDirectoryUnavailable
        }

        self.fileURL = documentsDirectory
            .appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadProfile() throws -> ProfileDraft? {
        if hasLoadedProfile { return cachedProfile }
        guard fileManager.fileExists(
            atPath: fileURL.path
        ) else {
            hasLoadedProfile = true
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let profile = try decoder.decode(
            ProfileDraft.self,
            from: data
        )
        cachedProfile = profile
        hasLoadedProfile = true
        return profile
    }

    func saveProfile(_ profile: ProfileDraft) throws {
        let data = try encoder.encode(profile)

        try data.write(
            to: fileURL,
            options: [.atomic]
        )
        cachedProfile = profile
        hasLoadedProfile = true
    }

    func deleteProfile() throws {
        guard fileManager.fileExists(
            atPath: fileURL.path
        ) else {
            cachedProfile = nil
            hasLoadedProfile = true
            return
        }

        try fileManager.removeItem(at: fileURL)
        cachedProfile = nil
        hasLoadedProfile = true
    }
}
