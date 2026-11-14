import CryptoKit
import Foundation

@MainActor
final class SecureChatSession {
    let match: CloudChatMatch
    let repository: SecureChatRepository
    private(set) var ownID: UUID?
    private var store: ChatKeyStore?
    private var state: ChatKeyStore.State?
    private var currentPeer: CloudChatBundle?
    private var peerCandidate: CloudChatBundle?
    private var allBundles: [CloudChatBundle] = []
    private var cursor: Int64?
    private var received: [UUID: ChatMessage] = [:]
    private var isBusy = false
    private(set) var needsDeviceReplacement = false
    private(set) var needsKeyConfirmation = false
    private(set) var isClosed = false
    var pendingCount: Int { state?.pending.count ?? 0 }
    var isReady: Bool { state != nil && currentPeer != nil && !needsKeyConfirmation && !needsDeviceReplacement && !isClosed }
    var codeIsVerified: Bool { state?.verifiedPeerDevice != nil && state?.verifiedPeerDevice == currentPeer?.deviceID && !needsKeyConfirmation }
    var safetyCode: String? {
        guard let state, let peer = peerCandidate ?? currentPeer,
              let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation:state.privateKey) else { return nil }
        return ChatCryptography.safetyCode(matchID:match.id,first:key.publicKey.rawRepresentation,second:peer.bundle.key)
    }
    init(match: CloudChatMatch, repository: SecureChatRepository) { self.match=match; self.repository=repository }
    private func identity() async throws {
        let uid = try await repository.userID()
        if let ownID { guard ownID == uid else { throw SupabaseSetupError.wrongAccount }; return }
        ownID=uid
        let store=ChatKeyStore(scope:repository.scope+"/"+uid.uuidString.lowercased()+"/"+match.id.uuidString.lowercased())
        self.store=store; state=try store.load()
    }
    private func save() throws { if let state { try store?.save(state) } }
    func prepare(replaceDevice: Bool = false) async throws {
        try await identity()
        guard var state, let ownID else { return }
        let bundles=try await repository.bundles(match.id)
        let mine=bundles.filter { $0.userID==ownID }
        let revoked=mine.contains { $0.deviceID==state.deviceID && $0.revokedAt != nil }
        if revoked || mine.contains(where: { $0.deviceID != state.deviceID && $0.revokedAt == nil }) {
            needsDeviceReplacement=true
            guard replaceDevice else { throw SecureChatError.replaceDevice }
            if revoked {
                state.archivedPrivateKeys[state.deviceID.uuidString]=state.privateKey
                state.privateKey=Curve25519.KeyAgreement.PrivateKey().rawRepresentation; state.deviceID=UUID(); state.verifiedPeerDevice=nil
            }
            // Switching is explicit. Pending old-device deliveries are discarded;
            // they cannot be safely re-sent under a different identity/message ID.
            state.pending=[]; self.state=state; try save()
        }
        let key=try Curve25519.KeyAgreement.PrivateKey(rawRepresentation:state.privateKey)
        try await repository.register(match.id,deviceID:state.deviceID,key:key.publicKey.rawRepresentation,replace:replaceDevice)
        needsDeviceReplacement=false
        try await refreshBundles()
    }
    private func refreshBundles() async throws {
        allBundles=try await repository.bundles(match.id)
        guard var state, let ownID else { return }
        guard let mine=allBundles.first(where:{$0.userID==ownID && $0.deviceID==state.deviceID && $0.revokedAt==nil}) else {
            needsDeviceReplacement=true; throw SecureChatError.replaceDevice
        }
        guard mine.bundle.key == (try Curve25519.KeyAgreement.PrivateKey(rawRepresentation:state.privateKey)).publicKey.rawRepresentation else {
            currentPeer=nil; throw SecureChatError.invalidEnvelope
        }
        guard let peer=allBundles.first(where:{$0.userID==match.partnerID && $0.revokedAt==nil}) else {
            currentPeer=nil; return
        }
        guard peer.bundle.protocol == ChatCryptography.protocolVersion, peer.bundle.key.count==32 else { currentPeer=nil; throw SecureChatError.invalidEnvelope }
        let stored=state.peerPins[peer.deviceID.uuidString]
        if let stored, stored != peer.bundle.key { currentPeer=nil; throw SecureChatError.invalidEnvelope }
        if state.currentPeerDevice == nil {
            state.peerPins[peer.deviceID.uuidString]=peer.bundle.key; state.currentPeerDevice=peer.deviceID
            self.state=state; try save()
        } else if state.currentPeerDevice != peer.deviceID || stored != peer.bundle.key {
            peerCandidate=peer; needsKeyConfirmation=true; throw SecureChatError.keyChanged
        }
        currentPeer=peer; peerCandidate=nil; needsKeyConfirmation=false
    }
    func confirmSecurityCode() throws {
        guard var state, let peer=peerCandidate ?? currentPeer else { return }
        state.peerPins[peer.deviceID.uuidString]=peer.bundle.key; state.currentPeerDevice=peer.deviceID
        state.verifiedPeerDevice=peer.deviceID
        state.pending.removeAll { $0.recipientDeviceID != peer.deviceID }
        self.state=state; try save()
        currentPeer=peer; peerCandidate=nil; needsKeyConfirmation=false
    }
    func queue(_ text: String) throws -> ChatMessage {
        guard isReady, var state, let ownID, let peer=currentPeer else { throw SecureChatError.noPeerDevice }
        let id=UUID()
        let context=ChatCryptography.Context(matchID:match.id,messageID:id,senderID:ownID,
            senderDeviceID:state.deviceID,recipientDeviceID:peer.deviceID)
        let ciphertext=try ChatCryptography.seal(text,context:context,
            senderKey:Curve25519.KeyAgreement.PrivateKey(rawRepresentation:state.privateKey),
            recipientKey:Curve25519.KeyAgreement.PublicKey(rawRepresentation:peer.bundle.key))
        state.pending.append(.init(id:id,senderDeviceID:state.deviceID,recipientDeviceID:peer.deviceID,ciphertext:ciphertext,createdAt:Date()))
        try store?.save(state); self.state=state
        return ChatMessage(id:id,sender:.currentUser,text:text,isRead:false)
    }
    func refresh() async throws -> [ChatMessage] {
        guard !isBusy else { return received.values.sorted { $0.sentAt < $1.sentAt } }
        isBusy=true; defer { isBusy=false }
        try await identity()
        isClosed=try await repository.isClosed(match.id)
        if !isClosed {
            if currentPeer==nil { try await prepare() } else { try await refreshBundles() }
        }
        guard let ownID, let state else { return [] }
        if !isClosed && isReady {
            for pending in state.pending {
                // Never silently redirect a queued ciphertext after device rotation.
                guard pending.senderDeviceID==self.state?.deviceID, pending.recipientDeviceID==currentPeer?.deviceID else { throw SecureChatError.keyChanged }
                try await repository.send(match.id,pending:pending)
                self.state?.pending.removeAll { $0.id==pending.id }; try save()
            }
        }
        // Fetch only the latest page on first open, then drain new pages in order.
        var page=try await repository.messages(match.id,after:cursor)
        repeat {
            for row in page {
                let message: ChatMessage
                do { message=try decrypt(row,ownID:ownID) }
                catch SecureChatError.unavailableKey {
                    message=ChatMessage(id:row.messageID,sender:.system,text:SecureChatError.unavailableKey.localizedDescription,sentAt:row.createdAt)
                }
                received[row.messageID]=message
                if row.senderID != ownID { newestPartnerRowID=max(newestPartnerRowID ?? 0,row.id) }
            }
            let next=page.map(\.id).max()
            if let next { cursor=max(cursor ?? 0,next) }
            guard page.count==100, next != nil else { break }
            page=try await repository.messages(match.id,after:cursor)
        } while !page.isEmpty
        return received.values.sorted { $0.sentAt < $1.sentAt }
    }
    private func decrypt(_ row: CloudChatMessage,ownID: UUID) throws -> ChatMessage {
        guard row.protocolVersion==ChatCryptography.protocolVersion, let state else { throw SecureChatError.unavailableKey }
        let fromMe=row.senderID==ownID
        guard fromMe || row.senderID==match.partnerID else { throw SecureChatError.invalidEnvelope }
        let myDevice=fromMe ? row.senderDeviceID : row.recipientDeviceID
        let privateData=myDevice==state.deviceID ? state.privateKey : state.archivedPrivateKeys[myDevice.uuidString]
        guard let privateData else { throw SecureChatError.unavailableKey }
        let senderPublic: Data
        if fromMe { senderPublic=try Curve25519.KeyAgreement.PrivateKey(rawRepresentation:privateData).publicKey.rawRepresentation }
        else {
            guard let pin=state.peerPins[row.senderDeviceID.uuidString] else { throw SecureChatError.unavailableKey }
            senderPublic=pin
        }
        let expected=ChatCryptography.Context(matchID:match.id,messageID:row.messageID,senderID:row.senderID,
            senderDeviceID:row.senderDeviceID,recipientDeviceID:row.recipientDeviceID)
        let text=try ChatCryptography.open(row.ciphertext,expected:expected,
            privateKey:Curve25519.KeyAgreement.PrivateKey(rawRepresentation:privateData),
            senderKey:Curve25519.KeyAgreement.PublicKey(rawRepresentation:senderPublic),isSender:fromMe)
        return ChatMessage(id:row.messageID,sender:fromMe ? .currentUser : .match,text:text,sentAt:row.createdAt,isRead:false)
    }
    func pendingMessages() -> [ChatMessage] {
        guard let state, let ownID else { return [] }
        return state.pending.compactMap { pending in
            guard let privateData = pending.senderDeviceID == state.deviceID ? state.privateKey : state.archivedPrivateKeys[pending.senderDeviceID.uuidString],
                  let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation:privateData) else { return nil }
            let context=ChatCryptography.Context(matchID:match.id,messageID:pending.id,senderID:ownID,
                senderDeviceID:pending.senderDeviceID,recipientDeviceID:pending.recipientDeviceID)
            guard let text=try? ChatCryptography.open(pending.ciphertext,expected:context,privateKey:key,senderKey:key.publicKey,isSender:true) else { return nil }
            return ChatMessage(id:pending.id,sender:.currentUser,text:text,sentAt:pending.createdAt,isRead:false)
        }
    }
    func end(block: Bool) async throws { try await identity(); try await repository.end(match.id,reason:block ? "blocked":"closed"); isClosed=true }
    func report(reason: String,details: String,endMatch: Bool = false) async throws {
        try await identity()
        try await repository.report(match.id,reason:reason,details:details,endMatch:endMatch)
        if endMatch { isClosed=true }
    }
    /// The newest server row of a message from the partner, for read receipts.
    private var newestPartnerRowID: Int64?
    private var lastMarkedRead: Int64?
    /// Tells the server everything received so far has been seen.
    func markRead() async throws {
        guard let newest=newestPartnerRowID, newest != lastMarkedRead, !isClosed else { return }
        try await repository.markRead(match.id,upTo:newest)
        lastMarkedRead=newest
    }
}
