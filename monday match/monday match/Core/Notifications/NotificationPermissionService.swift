import Foundation
import UserNotifications

enum NotificationPermissionState: Equatable {
    case notDetermined
    case denied
    case authorized
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
