import CryptoKit
import Foundation

/// Seals everything one phone hands another about its owner: a QR code, the
/// profile sent over the radio, and the card the server keeps for a match.
/// Without this app's key the bytes say nothing; with it, the app works out
/// a match and drops what it read (see `MatchSnapshot`).
///
/// This hides profiles from people, not from someone who takes the app
/// apart: the key travels inside every copy of the app, as it must for
/// phones that meet without a server. It is never stored as one value. It is
/// put together while the app runs from pieces that don't look like a key,
/// and every key number gives a different key, so a new app version can move
/// to a new key and stop reading old ones.
///
/// Sealed form: version (1 byte) ‖ key number (1) ‖ nonce (12) ‖ ciphertext ‖
/// tag (16), ChaCha20-Poly1305 with the first two bytes as associated data.
/// Kept as short as it can be: every byte makes the QR code denser.
enum ProfileSeal {
    static let version: UInt8 = 3
    /// The key new seals use.
    static let currentKeyNumber: UInt8 = 1
    /// Keys this build still opens. Leave older numbers out to stop reading
    /// what older versions sealed.
    static let readableKeyNumbers: ClosedRange<UInt8> = 1...1

    static let headerBytes = 2
    static let nonceBytes = 12
    static let tagBytes = 16

    static func seal(_ plaintext: Data, keyNumber: UInt8 = currentKeyNumber, nonce: Data? = nil) -> Data? {
        guard let key = key(number: keyNumber) else { return nil }
        let header = Data([version, keyNumber])
        do {
            let nonce = try nonce.map { try ChaChaPoly.Nonce(data: $0) } ?? ChaChaPoly.Nonce()
            let box = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce, authenticating: header)
            return header + box.combined
        } catch {
            return nil
        }
    }

    /// Nil for anything this build didn't seal or can no longer read, and for
    /// any changed byte.
    static func open(_ sealed: Data) -> Data? {
        let sealed = Data(sealed)
        guard sealed.count > headerBytes + nonceBytes + tagBytes,
              sealed[0] == version, readableKeyNumbers.contains(sealed[1]),
              let key = key(number: sealed[1]),
              let box = try? ChaChaPoly.SealedBox(combined: sealed.dropFirst(headerBytes)),
              let plaintext = try? ChaChaPoly.open(box, using: key, authenticating: sealed.prefix(headerBytes))
        else { return nil }
        return plaintext
    }

    // MARK: - Key

    private static func key(number: UInt8) -> SymmetricKey? {
        guard number > 0 else { return nil }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: material(number)),
                                      salt: Data(spread(lattice, by: number)),
                                      info: Data(spread(lattice.reversed(), by: ~number)) + [number],
                                      outputByteCount: 32)
    }

    /// 32 bytes from a counter-based mixer, folded with the tables below.
    private static func material(_ number: UInt8) -> [UInt8] {
        var state = drift[Int(number) % drift.count] &+ UInt64(number) &* 0x9E37_79B9_7F4A_7C15
        var bytes: [UInt8] = []
        for round in 0..<4 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            z ^= drift[(Int(number) &+ round &+ 1) % drift.count]
            withUnsafeBytes(of: z.bigEndian) { bytes += $0 }
        }
        return bytes
    }

    private static func spread<S: Sequence>(_ table: S, by number: UInt8) -> [UInt8] where S.Element == UInt8 {
        table.enumerated().map { $0.element ^ (number &* UInt8(truncatingIfNeeded: $0.offset &* 29 &+ 7)) }
    }

    private static let drift: [UInt64] = [
        0xC7AF_60B9_EB9C_C609, 0x3A10_B0EB_616E_4188, 0xC4EB_60D2_572E_4353, 0x9514_7F8B_8214_7E41,
        0x52F6_B75C_3604_95EF, 0x2749_FE8E_D6B1_991A, 0x8AA1_7BE7_5337_7D88,
    ]

    private static let lattice: [UInt8] = [197, 222, 200, 84, 73, 9, 233, 137, 20, 150, 88, 56, 48, 154, 181, 51]
}
