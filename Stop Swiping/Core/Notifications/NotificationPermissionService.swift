import Combine
import Foundation
import UserNotifications

enum NotificationPermissionState: Equatable {
    case notDetermined
    case denied
    case authorized
}

/// Account creation always comes first. A previous notification decision,
/// including a refusal, must not trigger another permission request.
enum AutoMatchingEntryStep: Equatable {
    case account, loading, notifications, matching

    static func resolve(hasAccount: Bool, notificationState: NotificationPermissionState?) -> Self {
        guard hasAccount else { return .account }
        switch notificationState {
        case nil: return .loading
        case .notDetermined: return .notifications
        case .authorized, .denied: return .matching
        }
    }
}

@MainActor
final class NotificationPermissionService: ObservableObject {
    @Published private(set) var state: NotificationPermissionState = .notDetermined
    @Published private(set) var isRequesting = false

    func refresh() async {
        let settings = await UNUserNotificationCenter.current()
            .notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            state = .authorized
        case .denied:
            state = .denied
        case .notDetermined:
            state = .notDetermined
        @unknown default:
            state = .notDetermined
        }
    }

    func requestAuthorization() async {
        isRequesting = true
        defer { isRequesting = false }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])

            state = granted ? .authorized : .denied
        } catch {
            state = .denied
        }
    }
}
