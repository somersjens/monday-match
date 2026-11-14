import Foundation
import UserNotifications

@MainActor
protocol EarlyAccessReminderScheduling {
    func requestPermission() async throws -> Bool
    func schedule(at date: Date, now: Date) async throws
    func cancel()
}

@MainActor
final class EarlyAccessReminder: NSObject, EarlyAccessReminderScheduling, UNUserNotificationCenterDelegate {
    static let identifier = "early-access.profile-deadline"
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        if center.delegate == nil { center.delegate = self }
    }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func schedule(at date: Date, now: Date) async throws {
        guard date > now else { return } // Relaunching never sends a late or duplicate nudge.
        let content = UNMutableNotificationContent()
        content.title = L10n("Your forever starts here ✨")
        content.body = L10n("One day left! Finish your profile to keep free, ad-free access forever. Your next connection is waiting 💙")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSince(now), repeats: false)
        try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
