import Foundation

protocol ProfileCreationStateStoring {
    func load() -> ProfileCreationState?
    func save(_ state: ProfileCreationState)
    func clear()
}

struct UserDefaultsProfileCreationStore: ProfileCreationStateStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "profileCreation.state.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> ProfileCreationState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ProfileCreationState.self, from: data)
    }

    func save(_ state: ProfileCreationState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

final class InMemoryProfileCreationStore: ProfileCreationStateStoring {
    private(set) var state: ProfileCreationState?

    init(state: ProfileCreationState? = nil) {
        self.state = state
    }

    func load() -> ProfileCreationState? { state }
    func save(_ state: ProfileCreationState) { self.state = state }
    func clear() { state = nil }
}
