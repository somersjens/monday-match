import CoreLocation
import CryptoKit
import XCTest
@testable import Stop_Swiping

/// The bytes iPhone and Android must agree on: the exchange channel, sealed
/// profile codes, match scores per category and chat envelopes. `interop/vectors.json` pins them;
/// the Android build runs the same checks against the same file. When the
/// file is missing this test writes it (commit it); afterwards any drift fails.
@MainActor
final class InteropVectorsTests: XCTestCase {
    private let today = CalendarDate(year: 2026, month: 11, day: 13)
    private var now: Date {
        BirthDateRules.calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 15))!
    }
    private static let vectorsURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("interop/vectors.json")

    private static let emmaHolder = ProfileHolder(bytes: Data([0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8]))
    private static let emmaNonce = Data(repeating: 0x5a, count: 12)

    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    private func bytes(_ hex: String) -> Data {
        Data(stride(from: 0, to: hex.count, by: 2).map {
            UInt8(hex[hex.index(hex.startIndex, offsetBy: $0)...].prefix(2), radix: 16)!
        })
    }
    private func key(_ fill: UInt8) throws -> Curve25519.KeyAgreement.PrivateKey {
        try .init(rawRepresentation: Data((0..<32).map { fill &+ UInt8($0) }))
    }

    // MARK: - Exchange channel

    /// RFC 7748 §6.1: the X25519 the channel uses is the standard one.
    func testX25519MatchesRFC7748() throws {
        let alice = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: bytes("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"))
        let bob = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: bytes("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f"))
        let shared = try alice.sharedSecretFromKeyAgreement(with: bob).withUnsafeBytes { Data($0) }
        XCTAssertEqual(hex(shared), "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742")
    }

    func testBothPhonesDeriveTheSameChannelAndCode() throws {
        let a = ExchangeWire.Handshake(), b = ExchangeWire.Handshake()
        var toB = try a.channel(theirHello: b.hello), toA = try b.channel(theirHello: a.hello)
        XCTAssertEqual(toB.confirmationCode, toA.confirmationCode)
        XCTAssertEqual(toB.confirmationCode.count, 6)
        for text in ["hello", "ready", String(repeating: "x", count: 10_000)] {
            XCTAssertEqual(try toA.open(toB.seal(Data(text.utf8))), Data(text.utf8))
            XCTAssertEqual(try toB.open(toA.seal(Data(text.utf8))), Data(text.utf8))
        }
    }

    func testReplayReorderAndTamperingAreRefused() throws {
        let a = ExchangeWire.Handshake(), b = ExchangeWire.Handshake()
        var sender = try a.channel(theirHello: b.hello), receiver = try b.channel(theirHello: a.hello)
        let first = try sender.seal(Data("one".utf8)), second = try sender.seal(Data("two".utf8))
        XCTAssertThrowsError(try receiver.open(second), "Out of order")
        XCTAssertEqual(try receiver.open(first), Data("one".utf8))
        XCTAssertThrowsError(try receiver.open(first), "Replayed")
        var tampered = second
        tampered[tampered.startIndex] ^= 1
        XCTAssertThrowsError(try receiver.open(tampered))
        // A third phone that saw both hellos can't read anything.
        var eavesdropper = try ExchangeWire.Handshake().channel(theirHello: a.hello)
        XCTAssertThrowsError(try eavesdropper.open(second))
    }

    func testMalformedHellosAreRefused() {
        let a = ExchangeWire.Handshake()
        XCTAssertThrowsError(try a.channel(theirHello: Data(a.hello.prefix(48))))
        var future = ExchangeWire.Handshake().hello
        future[future.startIndex] = 3
        XCTAssertThrowsError(try a.channel(theirHello: future)) {
            XCTAssertEqual($0 as? ExchangeWire.Failure, .unsupportedVersion)
        }
        XCTAssertThrowsError(try a.channel(theirHello: a.hello)) { XCTAssertEqual($0 as? ExchangeWire.Failure, .sameKey) }
    }

    func testFramesSurviveAnyBluetoothWriteSize() throws {
        let messages = [Data("short".utf8), Data((0..<5_000).map { UInt8($0 % 251) })]
        for mtu in [20, 182, 512] {
            var reassembler = ExchangeWire.Reassembler()
            var received: [Data] = []
            for message in messages {
                for piece in ExchangeWire.frames(for: message, mtu: mtu) {
                    XCTAssertLessThanOrEqual(piece.count, mtu)
                    received += try reassembler.append(piece)
                }
            }
            XCTAssertEqual(received, messages, "MTU \(mtu)")
        }
        var reassembler = ExchangeWire.Reassembler()
        XCTAssertThrowsError(try reassembler.append(Data([0xff, 0xff, 0xff, 0xff, 1])), "Absurd length")
    }

    // MARK: - Pinned vectors

    private func profile(name: String, gender: GenderIdentity, partnerGenders: Set<GenderIdentity>,
                         own: Int) -> ProfileCreationState {
        var state = ProfileCreationState(today: today, applicationLanguage: "nl")
        state.displayName = name
        state.dateOfBirth = CalendarDate(year: 1996, month: 4, day: 21)
        state.partnerAgeRange = PartnerAgeRange(minimum: 24, maximum: 40, isCustomized: true)
        state.heightCentimeters = 182
        state.gender = gender
        state.partnerGenders = partnerGenders
        state.languages = ["nl", "en"]
        state.location = SelectedLocation(coordinate: CLLocationCoordinate2D(latitude: 51.05, longitude: 3.72), source: .map)
        state.searchRadiusKilometers = 40
        var lifestyle = state.lifestyle
        lifestyle.hasChildren = false
        lifestyle.openToPartnerWithChildren = true
        lifestyle.futureChildren = .notSure
        for substance in Substance.allCases {
            lifestyle[substance] = SubstanceAnswer(ownLevel: 1, partnerMaximumLevel: 5)
        }
        for (index, question) in CompatibilityScaleQuestion.all.enumerated() {
            lifestyle[question] = CompatibilityScaleAnswer(own: (index + own) % 5 + 1, partner: (index * 3) % 5 + 1,
                                                           isPartnerCustomized: true, importance: index % 5 + 1)
        }
        state.lifestyle = lifestyle
        state.completedAt = now
        return state
    }

    private func currentVectors() throws -> [String: Any] {
        let emma = profile(name: "Emma", gender: .woman, partnerGenders: [.man], own: 0)
        let jens = profile(name: "Jens", gender: .man, partnerGenders: [.woman], own: 2)
        let report = MatchReport(you: emma.sharedCopy(today: today), them: jens.sharedCopy(today: today), on: today)
        func categories(_ fits: [MatchResult.CategoryFit]) -> [String: Any] {
            Dictionary(uniqueKeysWithValues: fits.map {
                ($0.category.rawValue, ["fit": $0.fitPercentage.map { $0 as Any } ?? NSNull(), "share": $0.sharePercentage])
            })
        }

        let a = ExchangeWire.Handshake(privateKey: try key(1), nonce: Data(repeating: 0xa1, count: 16))
        let b = ExchangeWire.Handshake(privateKey: try key(101), nonce: Data(repeating: 0xb2, count: 16))
        var channel = try a.channel(theirHello: b.hello)
        let plaintext = Data(#"{"ready":{}}"#.utf8)

        let sender = try key(201), recipient = try key(151)
        let ids = (0..<5).map { UUID(uuidString: String(format: "a7fa0000-0000-4000-8000-%012d", $0 + 1))! }
        let context = ChatCryptography.Context(matchID: ids[0], messageID: ids[1], senderID: ids[2],
                                               senderDeviceID: ids[3], recipientDeviceID: ids[4])
        return [
            "about": "Generated by Stop SwipingTests/InteropVectorsTests.swift. Android must reproduce every value.",
            "profile_code": [
                "today": "2026-11-13",
                "sealed_at": Int(now.timeIntervalSince1970),
                // The bits inside the seal.
                "emma_packed_base64": try XCTUnwrap(ProfileCode.encoded(emma, today: today)).base64EncodedString(),
                // Sealed with a fixed nonce; the app uses a random one.
                "emma_holder": hex(Self.emmaHolder.bytes),
                "emma_nonce": hex(Self.emmaNonce),
                "emma_sealed_base64": try XCTUnwrap(ProfileCode.sealed(emma, holder: Self.emmaHolder, today: today,
                                                                       now: now, nonce: Self.emmaNonce)).base64EncodedString(),
            ],
            "match_score": ["emma_for_jens": report.score(.yours), "jens_for_emma": report.score(.theirs),
                            "is_match": report.isMatch,
                            "emma_for_jens_categories": categories(report.categories(.yours)),
                            "jens_for_emma_categories": categories(report.categories(.theirs)),
                            "together_categories": categories(report.result.together)],
            "exchange": [
                "a_hello": hex(a.hello), "b_hello": hex(b.hello),
                "confirmation_code": channel.confirmationCode,
                "plaintext": String(decoding: plaintext, as: UTF8.self),
                "a_first_sealed": hex(try channel.seal(plaintext)),
            ],
            "chat": [
                "sender_private": hex(sender.rawRepresentation), "recipient_private": hex(recipient.rawRepresentation),
                "match_id": ids[0].uuidString.lowercased(),
                "message_id": ids[1].uuidString.lowercased(), "sender_id": ids[2].uuidString.lowercased(),
                "sender_device_id": ids[3].uuidString.lowercased(), "recipient_device_id": ids[4].uuidString.lowercased(),
                "plaintext": "Hoi Emma 👋",
                // HPKE uses a fresh ephemeral key, so this is one valid envelope, not the only one.
                "envelope": try ChatCryptography.seal("Hoi Emma 👋", context: context, senderKey: sender,
                                                      recipientKey: recipient.publicKey),
                "safety_code": ChatCryptography.safetyCode(matchID: ids[0], first: sender.publicKey.rawRepresentation,
                                                           second: recipient.publicKey.rawRepresentation),
            ],
        ]
    }

    func testPinnedVectorsStillHold() throws {
        let current = try currentVectors()
        guard let stored = try? Data(contentsOf: Self.vectorsURL) else {
            try FileManager.default.createDirectory(at: Self.vectorsURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: current, options: [.prettyPrinted, .sortedKeys])
                .write(to: Self.vectorsURL)
            return
        }
        let pinned = try XCTUnwrap(JSONSerialization.jsonObject(with: stored) as? [String: Any])
        for section in ["profile_code", "match_score", "exchange"] {
            XCTAssertEqual(NSDictionary(dictionary: pinned[section] as? [String: Any] ?? [:]),
                           NSDictionary(dictionary: current[section] as? [String: Any] ?? [:]), section)
        }

        // The stored sealed code still opens to the same profile and sender.
        let codes = try XCTUnwrap(pinned["profile_code"] as? [String: Any])
        let sealed = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(codes["emma_sealed_base64"] as? String)))
        let emma = try XCTUnwrap(ProfileCode.opened(sealed, today: today, now: now, expires: true))
        XCTAssertEqual(emma.profile.displayName, "Emma")
        XCTAssertEqual(emma.holder, Self.emmaHolder)
        XCTAssertEqual(emma.sealedAt, now)
        XCTAssertNil(ProfileCode.opened(sealed, today: today, now: now.addingTimeInterval(ProfileCode.codeLifetime + 1),
                                        expires: true), "Read from a camera, a code lasts a day.")

        // The stored chat envelope still opens, and the safety code is unchanged.
        let chat = try XCTUnwrap(pinned["chat"] as? [String: String])
        let sender = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes(chat["sender_private"]!))
        let recipient = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes(chat["recipient_private"]!))
        let context = ChatCryptography.Context(
            matchID: UUID(uuidString: chat["match_id"]!)!, messageID: UUID(uuidString: chat["message_id"]!)!,
            senderID: UUID(uuidString: chat["sender_id"]!)!, senderDeviceID: UUID(uuidString: chat["sender_device_id"]!)!,
            recipientDeviceID: UUID(uuidString: chat["recipient_device_id"]!)!)
        XCTAssertEqual(try ChatCryptography.open(chat["envelope"]!, expected: context, privateKey: recipient,
                                                 senderKey: sender.publicKey, isSender: false), chat["plaintext"])
        XCTAssertEqual(try ChatCryptography.open(chat["envelope"]!, expected: context, privateKey: sender,
                                                 senderKey: sender.publicKey, isSender: true), chat["plaintext"])
        XCTAssertEqual(chat["safety_code"], (current["chat"] as? [String: String])?["safety_code"])
    }
}
