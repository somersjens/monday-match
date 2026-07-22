import Foundation

enum ProfileRepositoryError: LocalizedError {
    case documentsDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            return "The app's local storage directory is unavailable."
        }
    }
}

struct FileProfileRepository: ProfileRepository {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL

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
        guard fileManager.fileExists(
            atPath: fileURL.path
        ) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(
            ProfileDraft.self,
            from: data
        )
    }

    func saveProfile(_ profile: ProfileDraft) throws {
        let data = try encoder.encode(profile)

        try data.write(
            to: fileURL,
            options: [.atomic]
        )
    }

    func deleteProfile() throws {
        guard fileManager.fileExists(
            atPath: fileURL.path
        ) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }
}
