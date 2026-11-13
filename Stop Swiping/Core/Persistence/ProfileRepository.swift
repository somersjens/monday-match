import Foundation

protocol ProfileRepository {
    func loadProfile() throws -> ProfileDraft?
    func saveProfile(_ profile: ProfileDraft) throws
    func deleteProfile() throws
}
