import CryptoKit
import XCTest
@testable import Stop_Swiping

@MainActor
final class SecureChatTests: XCTestCase {
    private func context() -> ChatCryptography.Context {
        .init(matchID:UUID(),messageID:UUID(),senderID:UUID(),senderDeviceID:UUID(),recipientDeviceID:UUID())
    }
    func testBothParticipantsCanDecryptAndServerHasOnlyCiphertext() throws {
        let sender=Curve25519.KeyAgreement.PrivateKey(), recipient=Curve25519.KeyAgreement.PrivateKey()
        let context=context(), text="Privébericht met een hart ♥️"
        let encrypted=try ChatCryptography.seal(text,context:context,senderKey:sender,recipientKey:recipient.publicKey)
        XCTAssertFalse(encrypted.contains(text))
        XCTAssertEqual(try ChatCryptography.open(encrypted,expected:context,privateKey:recipient,senderKey:sender.publicKey,isSender:false),text)
        XCTAssertEqual(try ChatCryptography.open(encrypted,expected:context,privateKey:sender,senderKey:sender.publicKey,isSender:true),text)
    }
    func testWrongPrivateKeyAndSenderCannotDecrypt() throws {
        let sender=Curve25519.KeyAgreement.PrivateKey(), recipient=Curve25519.KeyAgreement.PrivateKey(), attacker=Curve25519.KeyAgreement.PrivateKey()
        let context=context()
        let encrypted=try ChatCryptography.seal("secret",context:context,senderKey:sender,recipientKey:recipient.publicKey)
        XCTAssertThrowsError(try ChatCryptography.open(encrypted,expected:context,privateKey:attacker,senderKey:sender.publicKey,isSender:false))
        XCTAssertThrowsError(try ChatCryptography.open(encrypted,expected:context,privateKey:recipient,senderKey:attacker.publicKey,isSender:false))
    }
    func testTamperingAndCrossMatchReplayAreRejected() throws {
        let sender=Curve25519.KeyAgreement.PrivateKey(), recipient=Curve25519.KeyAgreement.PrivateKey(), context=context()
        let encrypted=try ChatCryptography.seal("secret",context:context,senderKey:sender,recipientKey:recipient.publicKey)
        var envelope=try JSONDecoder().decode(ChatCryptography.Envelope.self,from:Data(encrypted.utf8))
        envelope.recipient.ciphertext[0] ^= 1
        let changed=String(decoding:try JSONEncoder().encode(envelope),as:UTF8.self)
        XCTAssertThrowsError(try ChatCryptography.open(changed,expected:context,privateKey:recipient,senderKey:sender.publicKey,isSender:false))
        let other=ChatCryptography.Context(matchID:UUID(),messageID:context.messageID,senderID:context.senderID,
            senderDeviceID:context.senderDeviceID,recipientDeviceID:context.recipientDeviceID)
        XCTAssertThrowsError(try ChatCryptography.open(encrypted,expected:other,privateKey:recipient,senderKey:sender.publicKey,isSender:false))
    }
    func testMessageMetadataIsAuthenticatedEvenIfHeaderIsRewritten() throws {
        let sender=Curve25519.KeyAgreement.PrivateKey(), recipient=Curve25519.KeyAgreement.PrivateKey(), context=context()
        let encrypted=try ChatCryptography.seal("secret",context:context,senderKey:sender,recipientKey:recipient.publicKey)
        let original=try JSONDecoder().decode(ChatCryptography.Envelope.self,from:Data(encrypted.utf8))
        let replacement=ChatCryptography.Context(matchID:context.matchID,messageID:UUID(),senderID:context.senderID,
            senderDeviceID:context.senderDeviceID,recipientDeviceID:context.recipientDeviceID)
        let forged=ChatCryptography.Envelope(version:original.version,context:replacement,recipient:original.recipient,sender:original.sender)
        XCTAssertThrowsError(try ChatCryptography.open(String(decoding:JSONEncoder().encode(forged),as:UTF8.self),expected:replacement,
            privateKey:recipient,senderKey:sender.publicKey,isSender:false))
    }
    func testIndependentMessagesOpenOutOfOrderAndUseFreshEphemeralKeys() throws {
        let sender=Curve25519.KeyAgreement.PrivateKey(), recipient=Curve25519.KeyAgreement.PrivateKey(), context=context()
        let one=try ChatCryptography.seal("one",context:context,senderKey:sender,recipientKey:recipient.publicKey)
        let two=try ChatCryptography.seal("two",context:context,senderKey:sender,recipientKey:recipient.publicKey)
        XCTAssertNotEqual(one,two)
        XCTAssertEqual(try ChatCryptography.open(two,expected:context,privateKey:recipient,senderKey:sender.publicKey,isSender:false),"two")
        XCTAssertEqual(try ChatCryptography.open(one,expected:context,privateKey:recipient,senderKey:sender.publicKey,isSender:false),"one")
    }
    func testSecurityCodeIsSymmetricAndChangesWithKeyOrMatch() {
        let a=Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation, b=Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let match=UUID(), code=ChatCryptography.safetyCode(matchID:match,first:a,second:b)
        XCTAssertEqual(code,ChatCryptography.safetyCode(matchID:match,first:b,second:a))
        XCTAssertNotEqual(code,ChatCryptography.safetyCode(matchID:UUID(),first:a,second:b))
        XCTAssertNotEqual(code,ChatCryptography.safetyCode(matchID:match,first:a,second:Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation))
    }
    func testKeychainReloadAndAccountIsolation() throws {
        let a=ChatKeyStore(scope:"test-"+UUID().uuidString), b=ChatKeyStore(scope:"test-"+UUID().uuidString)
        defer { try? a.remove(); try? b.remove() }
        let first=try a.load(), second=try a.load(), other=try b.load()
        XCTAssertEqual(first.deviceID,second.deviceID); XCTAssertEqual(first.privateKey,second.privateKey)
        XCTAssertNotEqual(first.privateKey,other.privateKey)
    }
    func testAcknowledgementLossRetriesExactlySameEncryptedEnvelope() async throws {
        let repository=FakeSecureChatRepository()
        let match=CloudChatMatch(id:UUID(),partnerID:repository.partnerID,partnerName:"Test",ownScore:90,partnerScore:90)
        let keyStore=ChatKeyStore(scope:repository.scope+"/"+repository.identity.uuidString.lowercased()+"/"+match.id.uuidString.lowercased())
        defer { try? keyStore.remove() }
        let session=SecureChatSession(match:match,repository:repository)
        try await session.prepare()
        _=try session.queue("retry without duplicate")
        repository.loseNextAcknowledgement=true
        do { _=try await session.refresh(); XCTFail("Expected lost acknowledgement") } catch {}
        let persisted=try keyStore.load()
        XCTAssertEqual(persisted.pending.count,1)
        XCTAssertFalse(persisted.pending[0].ciphertext.contains("retry without duplicate"))
        let firstCiphertext=persisted.pending[0].ciphertext
        let messages=try await session.refresh()
        XCTAssertEqual(repository.sent.count,1); XCTAssertEqual(repository.sent.values.first?.ciphertext,firstCiphertext)
        XCTAssertEqual(messages.first?.text,"retry without duplicate"); XCTAssertEqual(session.pendingCount,0)
    }
    func testAccountSwitchStopsOldConversation() async throws {
        let repository=FakeSecureChatRepository()
        let match=CloudChatMatch(id:UUID(),partnerID:repository.partnerID,partnerName:"Test",ownScore:90,partnerScore:90)
        let keyStore=ChatKeyStore(scope:repository.scope+"/"+repository.identity.uuidString.lowercased()+"/"+match.id.uuidString.lowercased())
        defer { try? keyStore.remove() }
        let model=ChatViewModel(conversation:ChatConversation(matchID:match.id,participantName:"Test",messages:[]),
            secureSession:SecureChatSession(match:match,repository:repository))
        await model.refresh(); model.draftMessage="private draft"
        repository.identity=UUID()
        await model.refresh()
        XCTAssertFalse(model.canSend); XCTAssertTrue(model.conversation.isClosed)
        XCTAssertTrue(model.conversation.messages.isEmpty); XCTAssertTrue(model.draftMessage.isEmpty)
    }
    func testRewritingAnExistingDeviceKeyFailsClosed() async throws {
        let repository=FakeSecureChatRepository()
        let match=CloudChatMatch(id:UUID(),partnerID:repository.partnerID,partnerName:"Test",ownScore:90,partnerScore:90)
        let keyStore=ChatKeyStore(scope:repository.scope+"/"+repository.identity.uuidString.lowercased()+"/"+match.id.uuidString.lowercased())
        defer { try? keyStore.remove() }
        let session=SecureChatSession(match:match,repository:repository)
        try await session.prepare(); XCTAssertTrue(session.isReady)
        repository.peerKey=Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        do { _=try await session.refresh(); XCTFail("Same device ID must never change keys") } catch {}
        XCTAssertFalse(session.isReady)
    }
    func testChangedPeerKeyStopsSendingUntilCodeIsConfirmed() async throws {
        let repository=FakeSecureChatRepository()
        let match=CloudChatMatch(id:UUID(),partnerID:repository.partnerID,partnerName:"Test",ownScore:90,partnerScore:90)
        let keyStore=ChatKeyStore(scope:repository.scope+"/"+repository.identity.uuidString.lowercased()+"/"+match.id.uuidString.lowercased())
        defer { try? keyStore.remove() }
        let session=SecureChatSession(match:match,repository:repository)
        try await session.prepare(); XCTAssertTrue(session.isReady)
        repository.peerDevice=UUID(); repository.peerKey=Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        do { _=try await session.refresh(); XCTFail("Expected changed key") } catch {}
        XCTAssertTrue(session.needsKeyConfirmation); XCTAssertFalse(session.isReady)
        XCTAssertThrowsError(try session.queue("must not send"))
        try session.confirmSecurityCode(); XCTAssertTrue(session.isReady); XCTAssertTrue(session.codeIsVerified)
    }
}

@MainActor
private final class FakeSecureChatRepository: SecureChatRepository {
    let scope="test-repository-"+UUID().uuidString
    var identity=UUID(), partnerID=UUID(), peerDevice=UUID()
    var peerKey=Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
    var ownBundle: CloudChatBundle?
    var sent: [UUID:ChatPendingMessage]=[:]
    var loseNextAcknowledgement=false
    func userID() async throws -> UUID { identity }
    func currentMatch() async throws -> CloudChatMatch? { nil }
    func isClosed(_ matchID:UUID) async throws -> Bool { false }
    func bundles(_ matchID:UUID) async throws -> [CloudChatBundle] {
        [CloudChatBundle(userID:partnerID,deviceID:peerDevice,bundle:.init(protocol:ChatCryptography.protocolVersion,key:peerKey),revokedAt:nil)] + (ownBundle.map { [$0] } ?? [])
    }
    func register(_ matchID:UUID,deviceID:UUID,key:Data,replace:Bool) async throws {
        ownBundle=CloudChatBundle(userID:identity,deviceID:deviceID,bundle:.init(protocol:ChatCryptography.protocolVersion,key:key),revokedAt:nil)
    }
    func messages(_ matchID:UUID,after:Int64?) async throws -> [CloudChatMessage] {
        guard after==nil else { return [] }
        return sent.values.map { CloudChatMessage(id:1,senderID:identity,messageID:$0.id,senderDeviceID:$0.senderDeviceID,
            recipientDeviceID:$0.recipientDeviceID,ciphertext:$0.ciphertext,protocolVersion:ChatCryptography.protocolVersion,createdAt:$0.createdAt) }
    }
    func send(_ matchID:UUID,pending:ChatPendingMessage) async throws {
        sent[pending.id]=pending
        if loseNextAcknowledgement { loseNextAcknowledgement=false; throw URLError(.networkConnectionLost) }
    }
    func end(_ matchID:UUID,reason:String) async throws {}
    func report(_ matchID:UUID,reason:String,details:String) async throws {}
}
