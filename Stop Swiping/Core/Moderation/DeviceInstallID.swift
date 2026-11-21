import Foundation
import Security

/// A random ID for this phone, kept in the keychain so it survives deleting
/// and reinstalling the app. The server stores only a keyed hash of it, to
/// keep an account that was banned for reports from coming back on the same
/// phone under a new sign-in (202611200009 register_device).
///
/// "This device only": it never syncs through iCloud Keychain to the
/// person's other devices, and it is not restored onto a new phone.
enum DeviceInstallID {
    private static let service = "Hakketjak.monday-match.install-id.v1"
    private static let account = "install-id"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Nil only when the keychain refuses (it is locked before the first unlock).
    static func current() -> UUID? {
        if let stored = load() { return stored }
        let id = UUID()
        var item = query
        item[kSecValueData as String] = Data(id.uuidString.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem { return load() }
        return status == errSecSuccess ? id : nil
    }

    private static func load() -> UUID? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let text = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: text)
    }
}

extension Notification.Name {
    /// The server said this account is now banned (for example because this
    /// phone belonged to a banned account): the home screen asks again.
    static let moderationChanged = Notification.Name("stopSwiping.moderationChanged")
}
