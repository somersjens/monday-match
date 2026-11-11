import Foundation

protocol CloudProfileRepository {
    func loadProfile(userID: String) async throws -> CloudProfile?
    func saveProfile(
        _ profile: CloudProfile,
        userID: String
    ) async throws
}
