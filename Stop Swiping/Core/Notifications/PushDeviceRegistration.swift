import Foundation
import Supabase
import UIKit

/// Tells the server where this phone receives pushes and what the user
/// allows. The server applies the same switches, previews and quiet hours.
@MainActor
protocol PushDeviceRegistering {
    /// `language` picks the copy the server sends: the app's own language.
    func register(deviceID: UUID, token: String, timeZone: String, language: AppLanguage,
                  preferences: NotificationPreferences) async throws
    func unregister(deviceID: UUID) async throws
}

@MainActor
final class SupabasePushDeviceRegistration: PushDeviceRegistering {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    /// Debug builds use the development APNs entitlement.
    static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    func register(deviceID: UUID, token: String, timeZone: String, language: AppLanguage,
                  preferences: NotificationPreferences) async throws {
        struct Params: Encodable {
            let p_device_id: UUID
            let p_token: String
            let p_environment: String
            let p_time_zone: String
            let p_transactional: Bool
            let p_previews: Bool
            let p_match_ended_alerts: Bool
            let p_quiet_start: Int?
            let p_quiet_end: Int?
            let p_language: String
            /// The server keeps APNs and FCM tokens apart; Android sends "android".
            let p_platform: String
        }
        let quiet = QuietHours(preferences)
        try await client.rpc("register_push_device", params: Params(
            p_device_id: deviceID, p_token: token, p_environment: Self.environment, p_time_zone: timeZone,
            p_transactional: preferences.matchesAndMessages, p_previews: preferences.messagePreviews,
            p_match_ended_alerts: preferences.matchEndedAlerts,
            p_quiet_start: quiet?.start, p_quiet_end: quiet?.end, p_language: language.rawValue,
            p_platform: "ios")).execute()
    }

    func unregister(deviceID: UUID) async throws {
        try await client.rpc("unregister_push_device", params: ["p_device_id": deviceID.uuidString]).execute()
    }
}

extension Notification.Name {
    /// A push from the server: a match was made or ended, or a message arrived.
    static let serverDataChanged = Notification.Name("stopSwiping.serverDataChanged")
}

/// Receives the APNs device token, which SwiftUI has no hook for.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    /// Set by the app once the engine exists.
    @MainActor static var onToken: ((Data) -> Void)?
    @MainActor private static var pendingToken: Data?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if let onToken = Self.onToken { onToken(deviceToken) } else { Self.pendingToken = deviceToken }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulators and missing entitlements land here; local notifications still work.
    }

    /// A background push (a match ended, a new message) lets the app replan
    /// its local reminders while closed.
    nonisolated func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any])
        async -> UIBackgroundFetchResult {
        let payload = NotificationEngine.strings(userInfo)
        await Self.handleBackgroundPush(payload)
        // Every server push carries content-available, so this runs in the
        // foreground too: the match screen asks the server now.
        await MainActor.run {
            NotificationCenter.default.post(name: .serverDataChanged, object: nil, userInfo: payload)
        }
        return .newData
    }

    @MainActor private static func handleBackgroundPush(_ payload: [String: String]) async {
        await onBackgroundPush?(payload)
    }

    @MainActor static var onBackgroundPush: (([String: String]) async -> Void)?

    @MainActor static func connect(_ engine: NotificationEngine) {
        onToken = { [weak engine] token in engine?.didRegister(deviceToken: token) }
        onBackgroundPush = { [weak engine] userInfo in await engine?.handleBackgroundPush(userInfo) }
        if let token = pendingToken {
            pendingToken = nil
            engine.didRegister(deviceToken: token)
        }
    }
}
