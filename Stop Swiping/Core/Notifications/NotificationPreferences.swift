import Foundation

/// What the user allows, separate from the system permission. Transactional
/// notifications and nudges have their own switches, as do message previews
/// and match-ended alerts.
struct NotificationPreferences: Codable, Equatable {
    /// New matches, messages and unsent-message warnings.
    var matchesAndMessages = true
    /// Reminders and playful re-engagement.
    var tipsAndNudges = true
    /// A push when a match ends. Off by default: the app tells you in person
    /// the next time you open it, which is kinder than a lock-screen breakup.
    var matchEndedAlerts = false
    /// The sender's name in message notifications. Off hides it everywhere.
    var messagePreviews = true
    var quietHoursEnabled = true
    /// Hours on a 24-hour clock in the user's current time zone.
    var quietHoursStart = 22
    var quietHoursEnd = 9

    static let standard = NotificationPreferences()

    func allows(_ kind: NotificationKind) -> Bool {
        switch kind.category {
        case .account: true
        case .transactional: kind == .matchEnded ? matchesAndMessages && matchEndedAlerts : matchesAndMessages
        case .reminder, .engagement: tipsAndNudges
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Self.standard
        matchesAndMessages = try values.decodeIfPresent(Bool.self, forKey: .matchesAndMessages) ?? standard.matchesAndMessages
        tipsAndNudges = try values.decodeIfPresent(Bool.self, forKey: .tipsAndNudges) ?? standard.tipsAndNudges
        matchEndedAlerts = try values.decodeIfPresent(Bool.self, forKey: .matchEndedAlerts) ?? standard.matchEndedAlerts
        messagePreviews = try values.decodeIfPresent(Bool.self, forKey: .messagePreviews) ?? standard.messagePreviews
        quietHoursEnabled = try values.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? standard.quietHoursEnabled
        quietHoursStart = Self.hour(try values.decodeIfPresent(Int.self, forKey: .quietHoursStart)) ?? standard.quietHoursStart
        quietHoursEnd = Self.hour(try values.decodeIfPresent(Int.self, forKey: .quietHoursEnd)) ?? standard.quietHoursEnd
    }

    private static func hour(_ value: Int?) -> Int? { value.flatMap { (0...23).contains($0) ? $0 : nil } }
}

/// Quiet hours on the user's local wall clock.
struct QuietHours: Equatable {
    var start: Int
    var end: Int

    init(start: Int, end: Int) { self.start = start; self.end = end }
    init?(_ preferences: NotificationPreferences) {
        guard preferences.quietHoursEnabled, preferences.quietHoursStart != preferences.quietHoursEnd else { return nil }
        self.init(start: preferences.quietHoursStart, end: preferences.quietHoursEnd)
    }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return start < end ? (start..<end).contains(hour) : (hour >= start || hour < end)
    }

    /// The moment quiet hours end, if `date` falls inside them; `date` itself otherwise.
    func nextAllowed(after date: Date, calendar: Calendar) -> Date {
        guard contains(date, calendar: calendar) else { return date }
        let startOfEndHour = calendar.nextDate(after: date, matching: DateComponents(hour: end, minute: 0, second: 0),
                                               matchingPolicy: .nextTime) ?? date
        return startOfEndHour
    }
}

@MainActor
final class NotificationPreferencesStore {
    private let defaults: UserDefaults
    private let key = "notifications.preferences.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> NotificationPreferences {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(NotificationPreferences.self, from: $0) } ?? .standard
    }

    func save(_ preferences: NotificationPreferences) {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: key) }
    }

    func clear() { defaults.removeObject(forKey: key) }
}
