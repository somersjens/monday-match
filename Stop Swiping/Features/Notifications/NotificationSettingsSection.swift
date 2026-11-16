import SwiftUI
import UIKit

private struct NotificationEngineKey: EnvironmentKey {
    static let defaultValue: NotificationEngine? = nil
}

extension EnvironmentValues {
    /// The app's notification engine; nil in previews and tests.
    var notificationEngine: NotificationEngine? {
        get { self[NotificationEngineKey.self] }
        set { self[NotificationEngineKey.self] = newValue }
    }
}

/// The notification switches in the profile overview. Matches and messages
/// are separate from nudges, so turning off the sass never costs a message.
struct NotificationSettingsSection: View {
    @ObservedObject var engine: NotificationEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n("Notifications").uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(OnboardingTheme.secondaryText)
                .padding(.leading, 6)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(L10n("Notifications"))

            VStack(spacing: 0) {
                switch engine.permission {
                case .authorized:
                    switches
                case .notDetermined:
                    permissionRow(title: L10n("Turn on notifications"),
                                  detail: L10n("Hear about matches and messages when the app is closed."),
                                  button: L10n("Turn on")) {
                        Task { await engine.requestPermission() }
                    }
                case .denied:
                    permissionRow(title: L10n("Notifications are off"),
                                  detail: L10n("Allow them in Settings to hear about matches and messages."),
                                  button: L10n("Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
            .onboardingSurface(cornerRadius: 24)
        }
        .padding(.top, 12)
        .task { await engine.refreshPermission() }
    }

    @ViewBuilder
    private var switches: some View {
        let preferences = engine.preferences
        row(L10n("Matches & messages"), detail: nil, isOn: preferences.matchesAndMessages) { $0.matchesAndMessages.toggle() }
        divider
        row(L10n("Message previews"), detail: L10n("Show who wrote to you on the lock screen."),
            isOn: preferences.messagePreviews) { $0.messagePreviews.toggle() }
            .disabled(!preferences.matchesAndMessages)
        divider
        row(L10n("Match ended alerts"), detail: L10n("Otherwise you’ll see it the next time you open the app."),
            isOn: preferences.matchEndedAlerts) { $0.matchEndedAlerts.toggle() }
            .disabled(!preferences.matchesAndMessages)
        divider
        row(L10n("Tips & nudges"), detail: L10n("At most two a week. Never pushy, occasionally sassy."),
            isOn: preferences.tipsAndNudges) { $0.tipsAndNudges.toggle() }
        divider
        row(L10n("Quiet hours"),
            detail: L10n("Between \(Self.hour(preferences.quietHoursStart)) and \(Self.hour(preferences.quietHoursEnd)), anything that can wait, waits."),
            isOn: preferences.quietHoursEnabled) { $0.quietHoursEnabled.toggle() }
    }

    private static func hour(_ hour: Int) -> String { String(format: "%02d:00", hour) }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5).padding(.leading, 16)
    }

    private func row(_ title: String, detail: String?, isOn: Bool,
                     change: @escaping (inout NotificationPreferences) -> Void) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GlowToggle(isOn: isOn, label: title) {
                var updated = engine.preferences
                change(&updated)
                engine.setPreferences(updated)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
    }

    private func permissionRow(title: String, detail: String, button: String,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(button, action: action)
                .font(.system(.subheadline, weight: .semibold))
                .buttonStyle(.bordered)
                .tint(OnboardingTheme.cyan)
        }
        .padding(16)
    }
}
