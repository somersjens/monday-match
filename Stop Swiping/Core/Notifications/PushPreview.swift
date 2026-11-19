import Foundation

/// The name on a message push, filled in on the phone.
///
/// Apple (and, for Android, Google) can read every push payload, so the
/// server never puts a name in one: a message push only says which match has
/// how many new messages. With previews on, the app leaves the active match's
/// name and the preview copy in the shared app group, and the Notification
/// Service Extension (`Stop Swiping Notifications`) turns the plain "New
/// message" into "Sam sent you a message." The same payload drives the
/// future Android handler.
///
/// This file is compiled into both the app and the extension, so it only
/// uses Foundation.
nonisolated enum PushPreview {
    static let appGroup = "group.Hakketjak.monday-match"
    static let storageKey = "pushPreview.v1"

    struct Template: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let body: String
    }

    /// What the extension may know: names of active matches only, and only
    /// while previews are on.
    struct Snapshot: Codable, Equatable, Sendable {
        /// Lowercased match ID → the partner's display name.
        var names: [String: String] = [:]
        /// `message_new.preview` and `message_new.preview_batch`, in the app's language.
        var single: [Template] = []
        var batch: [Template] = []
    }

    static func load(from defaults: UserDefaults?) -> Snapshot? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot?, to defaults: UserDefaults?) {
        guard let defaults else { return }
        if let snapshot, !snapshot.names.isEmpty, let data = try? JSONEncoder().encode(snapshot) {
            if defaults.data(forKey: storageKey) != data { defaults.set(data, forKey: storageKey) }
        } else if defaults.object(forKey: storageKey) != nil {
            defaults.removeObject(forKey: storageKey)
        }
    }

    /// The named title and body for a push, or nil to keep the server's
    /// plain text: previews off, another kind, an unknown match, or copy
    /// that would leave a placeholder unfilled.
    static func resolve(_ userInfo: [AnyHashable: Any], snapshot: Snapshot?) -> (title: String, body: String)? {
        func string(_ key: String) -> String? {
            switch userInfo[key] {
            case let value as String: value
            case let value as NSNumber: value.stringValue
            default: nil
            }
        }
        guard let snapshot, string("preview") == "1", string("kind") == "message_new",
              let match = string("match_id")?.lowercased(),
              let name = snapshot.names[match]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        let count = max(Int(string("count") ?? "") ?? 1, 1)
        let templates = count > 1 ? snapshot.batch : snapshot.single
        guard !templates.isEmpty else { return nil }
        // Rotates by outbox row, like the server's own variants.
        let template = templates[abs(Int(string("outbox_id") ?? "") ?? 0) % templates.count]
        let values = ["match_name": String(name.prefix(40)), "count": String(count)]
        func fill(_ text: String) -> String {
            values.reduce(text) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
        }
        let title = fill(template.title), body = fill(template.body)
        guard !(title + body).contains("{") else { return nil }
        return (title, body)
    }
}
