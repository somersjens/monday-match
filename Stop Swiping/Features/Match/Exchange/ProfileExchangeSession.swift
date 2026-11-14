import Combine
import Foundation
import MultipeerConnectivity
import NearbyInteraction

/// Finds other phones that are sharing a profile, and exchanges profiles
/// with the one this phone is held against. It works without an account or
/// internet: the phones talk directly, encrypted, over Wi-Fi and Bluetooth,
/// and measure the distance between them with ultra wideband. Where that
/// can't be measured, both people tap instead.
@MainActor
final class ProfileExchangeSession: NSObject, ObservableObject {
    /// Someone nearby who is sharing their profile too.
    struct Person: Identifiable, Equatable {
        let id: String
        let name: String
        /// This side is ready and waits for theirs.
        var isWaiting: Bool
        /// Their side is ready and waits for this one.
        var wantsToExchange: Bool
    }

    /// Both profiles, exactly as they crossed.
    struct Result: Identifiable, Equatable {
        let id: UUID
        let you: ProfileCreationState
        let them: ProfileCreationState
    }

    /// Matches `NSBonjourServices` in Info.plist.
    static let serviceType = "stopswiping"
    /// How long this side stays ready without an answer.
    static let readyTimeout: Duration = .seconds(30)
    private static let invitationTimeout: TimeInterval = 20
    private static let maximumInvitations = 3

    @Published private(set) var isActive = false
    @Published private(set) var people: [Person] = []
    /// Something the user should know: a refusal, or a missing permission.
    @Published private(set) var notice: String?
    @Published private(set) var result: Result?

    private final class Link {
        let peer: MCPeerID
        let session: MCSession
        var proximity: NISession?
        var gate = ProximityGate()
        var timeout: Task<Void, Never>?

        init(peer: MCPeerID, session: MCSession) {
            self.peer = peer
            self.session = session
        }
    }

    private var localPeer: MCPeerID?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var negotiation: ProfileExchangeNegotiation?
    private var links: [String: Link] = [:]
    /// Phones in range that this one is responsible for inviting.
    private var invitations: [String: Int] = [:]

    // MARK: - Lifecycle

    /// Starts looking for other phones, offering a copy of `profile`.
    func start(profile: ProfileCreationState, today: CalendarDate? = nil) {
        guard !isActive, profile.canShareProfile else { return }
        let today = today ?? .today()
        let peer = MCPeerID(displayName: UUID().uuidString)
        localPeer = peer
        negotiation = ProfileExchangeNegotiation(profile: profile.sharedCopy(today: today), today: today)
        result = nil
        notice = nil

        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        isActive = true
    }

    func stop() {
        guard isActive else { return }
        let open = Array(links.values)
        stopLooking()
        for link in open { close(link) }
    }

    /// Both profiles have crossed. The connection stays open a moment longer,
    /// so the last message is never cut off on its way out.
    private func finish() {
        let open = Array(links.values)
        stopLooking()
        for link in open {
            link.timeout?.cancel()
            link.proximity?.invalidate()
            link.proximity = nil
            link.session.delegate = nil
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            for link in open { link.session.disconnect() }
        }
    }

    private func stopLooking() {
        isActive = false
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        links = [:]
        invitations = [:]
        negotiation = nil
        localPeer = nil
        people = []
        notice = nil
    }

    /// The user taps to exchange with this person, without holding the
    /// phones together.
    func confirm(_ id: String) {
        notice = nil
        makeReady(for: id)
    }

    /// The user says no, or takes their own offer back.
    func decline(_ id: String) {
        guard let effects = negotiation?.decline(id) else { return }
        links[id]?.timeout?.cancel()
        links[id]?.gate.reset()
        apply(effects)
    }

    // MARK: - Negotiation

    private func makeReady(for id: String) {
        guard let effects = negotiation?.confirm(id), !effects.isEmpty else { return }
        links[id]?.timeout?.cancel()
        links[id]?.timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.readyTimeout)
            guard !Task.isCancelled else { return }
            self?.decline(id)
        }
        apply(effects)
    }

    private func apply(_ effects: [ProfileExchangeNegotiation.Effect]) {
        for effect in effects {
            switch effect {
            case .send(let message, let id):
                guard let link = links[id], let data = message.encoded() else { continue }
                try? link.session.send(data, toPeers: [link.peer], with: .reliable)
            case .completed(_, let profile):
                guard let you = negotiation?.profile else { continue }
                result = Result(id: UUID(), you: you, them: profile)
                finish()
                return
            case .declined(let id):
                links[id]?.timeout?.cancel()
                links[id]?.gate.reset()
                if let name = negotiation?.peers[id]?.name, !name.isEmpty {
                    notice = L10n("\(name) didn’t exchange profiles.")
                }
            }
        }
        publishPeople()
    }

    private func publishPeople() {
        people = (negotiation?.peers ?? [:])
            .filter { $0.value.hasGreeted && $0.value.isCompatible && links[$0.key] != nil }
            .map { Person(id: $0.key, name: $0.value.name, isWaiting: $0.value.localReady,
                          wantsToExchange: $0.value.remoteReady) }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    // MARK: - Connections

    private func makeLink(to peer: MCPeerID) -> Link? {
        guard let localPeer else { return nil }
        let session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        let link = Link(peer: peer, session: session)
        if let old = links.updateValue(link, forKey: peer.displayName) { close(old) }
        return link
    }

    private func close(_ link: Link) {
        link.timeout?.cancel()
        link.proximity?.invalidate()
        link.proximity = nil
        link.session.delegate = nil
        link.session.disconnect()
    }

    /// Both phones see each other; only the one with the larger ID invites,
    /// so two invitations never cross.
    private func found(_ peer: MCPeerID) {
        guard isActive, let localPeer, localPeer.displayName > peer.displayName else { return }
        invitations[peer.displayName] = 0
        invite(peer)
    }

    private func invite(_ peer: MCPeerID) {
        let id = peer.displayName
        guard isActive, let attempts = invitations[id], attempts < Self.maximumInvitations,
              links[id] == nil, let browser, let link = makeLink(to: peer) else { return }
        invitations[id] = attempts + 1
        browser.invitePeer(peer, to: link.session, withContext: nil, timeout: Self.invitationTimeout)
    }

    private func lost(_ id: String) {
        invitations[id] = nil
    }

    private func invited(by peer: MCPeerID, answer: (Bool, MCSession?) -> Void) {
        guard isActive, let link = makeLink(to: peer) else {
            answer(false, nil)
            return
        }
        answer(true, link.session)
    }

    private func connectionChanged(_ id: String, state: MCSessionState) {
        guard isActive, let link = links[id] else { return }
        switch state {
        case .connected:
            greet(id, over: link)
        case .notConnected:
            links[id] = nil
            close(link)
            apply(negotiation?.disconnected(id) ?? [])
            // A dropped or failed connection is tried again while the other
            // phone is still in range.
            guard invitations[id] != nil else { return }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.invite(link.peer)
            }
        default:
            break
        }
    }

    /// Greets once per connection, whichever comes first: the news that it
    /// opened, or the other phone's own greeting.
    private func greet(_ id: String, over link: Link) {
        guard negotiation?.peers[id] == nil else { return }
        let token = startMeasuring(link)
        apply(negotiation?.connected(id, proximityToken: token) ?? [])
    }

    private func received(_ data: Data, from id: String) {
        guard isActive, let link = links[id], let message = ProfileExchangeMessage.decoded(data) else { return }
        greet(id, over: link)
        guard let effects = negotiation?.received(message, from: id) else { return }
        if case .hello = message { measure(link, theirToken: negotiation?.peers[id]?.proximityToken) }
        apply(effects)
    }

    // MARK: - Distance

    /// Prepares a distance measurement with one phone and returns the token
    /// that phone needs to take part, or nil when this phone can't measure.
    private func startMeasuring(_ link: Link) -> Data? {
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else { return nil }
        let session = NISession()
        session.delegateQueue = .main
        session.delegate = self
        guard let token = session.discoveryToken,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            session.invalidate()
            return nil
        }
        link.proximity = session
        return data
    }

    private func measure(_ link: Link, theirToken: Data?) {
        guard let session = link.proximity else { return }
        guard let theirToken,
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: theirToken) else {
            session.invalidate()
            link.proximity = nil
            return
        }
        session.run(NINearbyPeerConfiguration(peerToken: token))
    }

    private func link(measuredBy session: ObjectIdentifier) -> (id: String, link: Link)? {
        links.first { $0.value.proximity.map(ObjectIdentifier.init) == session }.map { ($0.key, $0.value) }
    }

    private func measured(_ meters: Double?, by session: ObjectIdentifier) {
        guard isActive, let (id, link) = link(measuredBy: session) else { return }
        if link.gate.isTogether(afterReading: meters) {
            link.gate.reset()
            makeReady(for: id)
        }
    }

    /// The other phone moved out of range, or the app was in the background:
    /// measuring resumes with the same configuration.
    private func resumeMeasuring(_ session: ObjectIdentifier) {
        guard isActive, let (_, link) = link(measuredBy: session), let proximity = link.proximity,
              let configuration = proximity.configuration else { return }
        link.gate.reset()
        proximity.run(configuration)
    }

    /// Measuring stopped for good, for instance because the user didn't
    /// allow it. Tapping still works.
    private func stoppedMeasuring(_ session: ObjectIdentifier) {
        guard let (_, link) = link(measuredBy: session) else { return }
        link.proximity = nil
        link.gate.reset()
    }

    private func failedToStart() {
        guard isActive else { return }
        notice = L10n("Allow access to your local network in Settings to exchange profiles.")
    }
}

/// Framework objects that are only handed on to the main actor.
private struct Handoff<Value>: @unchecked Sendable {
    let value: Value
}

// MARK: - Finding phones

extension ProfileExchangeSession: MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        let peer = Handoff(value: peerID)
        Task { @MainActor in self.found(peer.value) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let id = peerID.displayName
        Task { @MainActor in self.lost(id) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in self.failedToStart() }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let handoff = Handoff(value: (peerID, invitationHandler))
        Task { @MainActor in self.invited(by: handoff.value.0, answer: handoff.value.1) }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in self.failedToStart() }
    }
}

// MARK: - Talking

extension ProfileExchangeSession: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let id = peerID.displayName
        Task { @MainActor in self.connectionChanged(id, state: state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let id = peerID.displayName
        Task { @MainActor in self.received(data, from: id) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String,
                             fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Measuring

extension ProfileExchangeSession: NISessionDelegate {
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        let id = ObjectIdentifier(session)
        let meters = nearbyObjects.first?.distance.map(Double.init)
        Task { @MainActor in self.measured(meters, by: id) }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject],
                             reason: NINearbyObject.RemovalReason) {
        guard reason == .timeout else { return }
        let id = ObjectIdentifier(session)
        Task { @MainActor in self.resumeMeasuring(id) }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        let id = ObjectIdentifier(session)
        Task { @MainActor in self.resumeMeasuring(id) }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        let id = ObjectIdentifier(session)
        Task { @MainActor in self.stoppedMeasuring(id) }
    }
}
