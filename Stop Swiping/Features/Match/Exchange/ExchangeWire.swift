import CryptoKit
import Foundation

/// The phone-to-phone exchange as bytes, independent of the radio, so an
/// iPhone and an Android phone can exchange profiles over Bluetooth LE.
///
/// MultipeerConnectivity (today's transport) only connects Apple devices and
/// encrypts on its own. Bluetooth LE connects both platforms but encrypts
/// nothing an app can rely on, so the channel does that itself:
///
/// 1. Each phone sends a 49-byte `hello`: version, a fresh X25519 public key
///    and a 16-byte random nonce.
/// 2. Both derive the same keys: X25519, then HKDF-SHA256 with the two nonces
///    as salt and both public keys in the info, ordered so both sides agree.
///    Each direction has its own key; a six-digit code from the same
///    derivation can be compared on both screens.
/// 3. Every `ProfileExchangeMessage` is sealed with ChaCha20-Poly1305 and a
///    per-direction counter as nonce, so nothing can be replayed, reordered
///    or dropped unnoticed.
/// 4. `frames(for:mtu:)` splits a sealed message into pieces that fit one
///    Bluetooth write; `Reassembler` puts them back together.
///
/// Compiled as plain Swift, so the Android app (built with Skip) runs this
/// exact code. docs/cross-platform-exchange.md describes the whole protocol;
/// `interop/vectors.json` pins its bytes.
nonisolated enum ExchangeWire {
    static let version: UInt8 = 2
    static let protocolLabel = Data("stopswiping-exchange-v2".utf8)
    static let helloBytes = 1 + 32 + 16
    /// Same bound as `ProfileExchangeMessage.maximumBytes`; sealed adds the tag.
    static let maximumPlaintextBytes = 256 * 1024
    static let maximumMessageBytes = maximumPlaintextBytes + 16

    enum Failure: Error, Equatable {
        case malformedHello, unsupportedVersion, sameKey, tooLarge, malformedFrame, authenticationFailed
    }

    /// One side of the handshake, before the other side's hello arrived.
    struct Handshake {
        let privateKey: Curve25519.KeyAgreement.PrivateKey
        let nonce: Data

        init(privateKey: Curve25519.KeyAgreement.PrivateKey = .init(), nonce: Data? = nil) {
            self.privateKey = privateKey
            self.nonce = nonce ?? Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        }

        var hello: Data { Data([ExchangeWire.version]) + privateKey.publicKey.rawRepresentation + nonce }

        func channel(theirHello: Data) throws -> Channel {
            let hello = Data(theirHello)
            guard hello.count == ExchangeWire.helloBytes else { throw Failure.malformedHello }
            guard hello[hello.startIndex] == ExchangeWire.version else { throw Failure.unsupportedVersion }
            let theirKeyBytes = hello.subdata(in: hello.startIndex + 1 ..< hello.startIndex + 33)
            let theirNonce = hello.subdata(in: hello.startIndex + 33 ..< hello.endIndex)
            let ours = privateKey.publicKey.rawRepresentation
            guard theirKeyBytes != ours else { throw Failure.sameKey }
            let theirKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirKeyBytes)
            let shared = try privateKey.sharedSecretFromKeyAgreement(with: theirKey)

            // Ordered by public key, so both phones compute identical inputs.
            let weAreFirst = ours.lexicographicallyPrecedes(theirKeyBytes)
            let (firstKey, secondKey) = weAreFirst ? (ours, theirKeyBytes) : (theirKeyBytes, ours)
            let (firstNonce, secondNonce) = weAreFirst ? (nonce, theirNonce) : (theirNonce, nonce)
            let material = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: firstNonce + secondNonce,
                                                          sharedInfo: ExchangeWire.protocolLabel + firstKey + secondKey,
                                                          outputByteCount: 72)
            let bytes = material.withUnsafeBytes { Data($0) }
            let firstToSecond = SymmetricKey(data: bytes.subdata(in: 0..<32))
            let secondToFirst = SymmetricKey(data: bytes.subdata(in: 32..<64))
            let code = bytes.subdata(in: 64..<72).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } % 1_000_000
            return Channel(sending: weAreFirst ? firstToSecond : secondToFirst,
                           receiving: weAreFirst ? secondToFirst : firstToSecond,
                           confirmationCode: String(format: "%06llu", code))
        }
    }

    /// An established, encrypted conversation with one other phone.
    struct Channel {
        fileprivate let sending: SymmetricKey
        fileprivate let receiving: SymmetricKey
        /// Six digits both phones show; equal codes mean nobody sits in between.
        let confirmationCode: String
        private(set) var sent: UInt64 = 0
        private(set) var received: UInt64 = 0

        private static func nonce(_ counter: UInt64) throws -> ChaChaPoly.Nonce {
            try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + withUnsafeBytes(of: counter.bigEndian) { Data($0) })
        }

        mutating func seal(_ plaintext: Data) throws -> Data {
            guard plaintext.count <= ExchangeWire.maximumPlaintextBytes else { throw Failure.tooLarge }
            let box = try ChaChaPoly.seal(plaintext, using: sending, nonce: Self.nonce(sent),
                                          authenticating: ExchangeWire.protocolLabel)
            sent += 1
            return box.ciphertext + box.tag
        }

        mutating func open(_ sealed: Data) throws -> Data {
            guard sealed.count >= 16, sealed.count <= ExchangeWire.maximumMessageBytes else { throw Failure.tooLarge }
            let sealed = Data(sealed)
            do {
                let box = try ChaChaPoly.SealedBox(nonce: Self.nonce(received),
                                                   ciphertext: sealed.prefix(sealed.count - 16),
                                                   tag: sealed.suffix(16))
                let plaintext = try ChaChaPoly.open(box, using: receiving, authenticating: ExchangeWire.protocolLabel)
                received += 1
                return plaintext
            } catch {
                throw Failure.authenticationFailed
            }
        }
    }

    /// A 4-byte big-endian length, then the bytes, cut into pieces of at most
    /// `mtu` bytes (a Bluetooth write; at least 20).
    static func frames(for message: Data, mtu: Int) -> [Data] {
        let size = max(mtu, 20)
        let whole = withUnsafeBytes(of: UInt32(message.count).bigEndian) { Data($0) } + message
        return stride(from: 0, to: whole.count, by: size).map { whole.subdata(in: $0 ..< min($0 + size, whole.count)) }
    }

    /// Collects pieces until whole messages are complete.
    struct Reassembler {
        private var buffer = Data()

        mutating func append(_ piece: Data) throws -> [Data] {
            buffer.append(piece)
            var messages: [Data] = []
            while buffer.count >= 4 {
                let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                guard length > 0, length <= ExchangeWire.maximumMessageBytes else {
                    buffer.removeAll()
                    throw Failure.malformedFrame
                }
                guard buffer.count >= 4 + length else { break }
                messages.append(buffer.subdata(in: buffer.startIndex + 4 ..< buffer.startIndex + 4 + length))
                buffer = Data(buffer.dropFirst(4 + length))
            }
            return messages
        }
    }
}
