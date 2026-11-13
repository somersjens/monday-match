import Foundation

final class InMemoryProfileRepository: ProfileRepository {
    private var profile: ProfileDraft?

    init(profile: ProfileDraft? = nil) {
        self.profile = profile
    }

    func loadProfile() throws -> ProfileDraft? {
        profile
    }

    func saveProfile(_ profile: ProfileDraft) throws {
        self.profile = profile
    }

    func deleteProfile() throws {
        profile = nil
    }
}
