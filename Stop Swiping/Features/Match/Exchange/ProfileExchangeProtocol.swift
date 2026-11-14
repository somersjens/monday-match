import CoreLocation
import Foundation

/// What two phones say to each other while exchanging profiles. A profile
/// only travels once both sides have said they are ready, each on their own
/// evidence: their own measurement that the phones are held together, or
/// their owner's tap.
enum ProfileExchangeMessage: Codable, Equatable {
    static let version = 1
    /// Far above any real profile; anything larger is not read at all.
    static let maximumBytes = 256 * 1024

    struct Hello: Codable, Equatable {
        var version = ProfileExchangeMessage.version
        /// The first name shown before anything is exchanged.
        var name: String
        /// An archived `NIDiscoveryToken`, when this phone can measure the
        /// distance to the other one.
        var proximityToken: Data?
    }

    case hello(Hello)
    case ready
    case profile(ProfileCreationState)
    case decline

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decoded(_ data: Data) -> ProfileExchangeMessage? {
        guard data.count <= maximumBytes else { return nil }
        return try? JSONDecoder().decode(ProfileExchangeMessage.self, from: data)
    }
}

extension ProfileCreationState {
    /// The copy that leaves this phone: everything matching needs, and
    /// nothing more exact or more private than that.
    func sharedCopy(today: CalendarDate) -> ProfileCreationState {
        var copy = self
        copy.currentStep = .dateOfBirth
        copy.religionPhase = .own
        copy.isUnderageLocked = false
        copy.displayName = ProfileNameRules.normalized(displayName)
        // Only the age is shared: a birthday on 1 January gives the same age
        // all year, so the real day and month stay on this phone.
        if let age = age(on: today) {
            let birthday = CalendarDate(year: today.year - age, month: 1, day: 1)
            copy.dateOfBirth = birthday
            copy.birthDateBaseline = birthday
            copy.birthDateSelection = birthday
        }
        // About a kilometre, like the location kept in the cloud.
        if let location {
            func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }
            copy.location = SelectedLocation(
                coordinate: CLLocationCoordinate2D(latitude: rounded(location.latitude),
                                                   longitude: rounded(location.longitude)),
                source: .map, placeName: location.placeName
            )
        }
        // Appearance scores and the photo are for auto matching only.
        copy.autoMatching = AutoMatchingSettings()
        copy.profilePrivacyConsent = nil
        copy.hasUnderstoodExplanation = nil
        copy.hasCompletedDemo = nil
        copy.hasUsedProfileExchange = nil
        return copy
    }

    /// A profile received from another phone, or nil when it can't be
    /// trusted: unfinished, nameless or not an adult.
    func receivedCopy(today: CalendarDate) -> ProfileCreationState? {
        var copy = sharedCopy(today: today)
        guard completedAt != nil, !copy.displayName.isEmpty,
              let birthday = dateOfBirth, BirthDateRules.exists(birthday),
              let age = age(on: today), (BirthDateRules.minimumAge...BirthDateRules.oldestSelectableAge).contains(age)
        else { return nil }
        copy.heightCentimeters = HeightRules.clamped(heightCentimeters)
        copy.searchRadiusKilometers = SearchRadiusRules.clamped(searchRadiusKilometers)
        copy.languages = Array(languages.prefix(20))
        if let location, !CLLocationCoordinate2DIsValid(location.coordinate) { copy.location = nil }
        return copy
    }
}

/// The exchange's rules, separate from radios and screens: who has greeted,
/// who is ready, and when a profile may be sent or accepted.
struct ProfileExchangeNegotiation {
    enum Effect: Equatable {
        case send(ProfileExchangeMessage, to: String)
        /// Both profiles have crossed.
        case completed(peer: String, profile: ProfileCreationState)
        /// The other person said no, or took the offer back.
        case declined(peer: String)
    }

    struct Peer: Equatable {
        /// Empty until the other phone has greeted.
        var name = ""
        var proximityToken: Data?
        var hasGreeted = false
        var isCompatible = true
        var localReady = false
        var remoteReady = false
        var sentProfile = false
    }

    /// The copy of the user's profile that is sent, and matched with.
    let profile: ProfileCreationState
    let today: CalendarDate
    private(set) var peers: [String: Peer] = [:]
    /// Once ready for one person, everyone else waits.
    private(set) var engagedPeer: String?

    init(profile: ProfileCreationState, today: CalendarDate) {
        self.profile = profile
        self.today = today
    }

    /// A connection opened: greet, with this phone's token for measuring
    /// the distance when it has one.
    mutating func connected(_ peer: String, proximityToken: Data?) -> [Effect] {
        guard peers[peer] == nil else { return [] }
        peers[peer] = Peer()
        return [.send(.hello(.init(name: profile.displayName, proximityToken: proximityToken)), to: peer)]
    }

    mutating func disconnected(_ peer: String) -> [Effect] {
        guard peers.removeValue(forKey: peer) != nil else { return [] }
        guard engagedPeer == peer else { return [] }
        engagedPeer = nil
        return [.declined(peer: peer)]
    }

    /// This side is ready: the phones are held together, or the user tapped.
    mutating func confirm(_ peer: String) -> [Effect] {
        guard var state = peers[peer], state.hasGreeted, state.isCompatible, !state.localReady,
              engagedPeer == nil || engagedPeer == peer else { return [] }
        state.localReady = true
        engagedPeer = peer
        var effects: [Effect] = [.send(.ready, to: peer)]
        if state.remoteReady {
            state.sentProfile = true
            effects.append(.send(.profile(profile), to: peer))
        }
        peers[peer] = state
        return effects
    }

    /// Says no to an offer, or takes back this side's own.
    mutating func decline(_ peer: String) -> [Effect] {
        guard var state = peers[peer], state.hasGreeted, !state.sentProfile else { return [] }
        state.localReady = false
        state.remoteReady = false
        peers[peer] = state
        if engagedPeer == peer { engagedPeer = nil }
        return [.send(.decline, to: peer)]
    }

    mutating func received(_ message: ProfileExchangeMessage, from peer: String) -> [Effect] {
        guard var state = peers[peer] else { return [] }
        defer { if peers[peer] != nil { peers[peer] = state } }
        switch message {
        case .hello(let hello):
            guard !state.hasGreeted else { return [] }
            state.hasGreeted = true
            state.name = ProfileNameRules.normalized(hello.name)
            state.proximityToken = hello.proximityToken
            state.isCompatible = hello.version == ProfileExchangeMessage.version && !state.name.isEmpty
            return []
        case .ready:
            guard state.hasGreeted, state.isCompatible, !state.remoteReady else { return [] }
            state.remoteReady = true
            guard state.localReady, !state.sentProfile else { return [] }
            state.sentProfile = true
            return [.send(.profile(profile), to: peer)]
        case .profile(let theirs):
            // Only someone this side is ready for may deliver a profile, and
            // only in exchange for this side's own.
            guard state.localReady, state.remoteReady, state.sentProfile, engagedPeer == peer else { return [] }
            guard let received = theirs.receivedCopy(today: today) else {
                state.localReady = false
                state.remoteReady = false
                engagedPeer = nil
                return [.declined(peer: peer)]
            }
            return [.completed(peer: peer, profile: received)]
        case .decline:
            guard state.hasGreeted, !state.sentProfile else { return [] }
            let wasInvolved = state.localReady || state.remoteReady
            state.localReady = false
            state.remoteReady = false
            if engagedPeer == peer { engagedPeer = nil }
            return wasInvolved ? [.declined(peer: peer)] : []
        }
    }
}

/// Decides when two phones are being held together, from a stream of
/// distance readings. One stray reading is never enough.
struct ProximityGate {
    /// Phones held against each other read well under this; people standing
    /// side by side with phones in hand read far over it.
    static let distanceMeters = 0.15
    static let requiredReadings = 3

    private var closeReadings = 0

    /// True once enough consecutive readings were close.
    mutating func isTogether(afterReading meters: Double?) -> Bool {
        guard let meters, meters.isFinite, meters >= 0, meters <= Self.distanceMeters else {
            closeReadings = 0
            return false
        }
        closeReadings += 1
        return closeReadings >= Self.requiredReadings
    }

    mutating func reset() { closeReadings = 0 }
}
