import Foundation

/// What the app sends once the system permission is granted. There are no
/// switches: you get everything or, with notifications off in Settings,
/// nothing. The fields stay so the planner and the push registration keep
/// one place to read them from.
struct NotificationPreferences: Equatable {
    /// New matches, messages and unsent-message warnings.
    var matchesAndMessages = true
    /// Reminders and playful re-engagement.
    var tipsAndNudges = true
    /// A push when a match ends.
    var matchEndedAlerts = true
    /// The sender's name in message notifications.
    var messagePreviews = true
    /// Nudges that can wait, wait until morning.
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
