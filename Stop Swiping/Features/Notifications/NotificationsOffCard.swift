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

/// Shown on the first auto matching screen once notifications were refused.
/// The app already asked once, so the only way back is the system's
/// Settings. Allowed there, the card confirms it where the button was and
/// then sinks away.
struct NotificationsOffCard: View {
    @ObservedObject var engine: NotificationEngine

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .hidden

    private enum Phase { case hidden, off, turnedOn }

    var body: some View {
        Group {
            if phase != .hidden {
                card
                    .transition(.onboardingReveal(reduceMotion: reduceMotion))
            }
        }
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: phase)
        .onChange(of: engine.permission, initial: true) { _, permission in update(for: permission) }
        .task { await engine.refreshPermission() }
    }

    private var card: some View {
        HStack(spacing: 14) {
            Text(phase == .turnedOn ? L10n("Notifications are on") : L10n("Notifications are off"))
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(OnboardingTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.opacity)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .trailing) {
                // Keeps the button's room, so the row doesn't jump when it goes.
                settingsButton
                    .opacity(phase == .off ? 1 : 0)
                    .blur(radius: phase == .off || reduceMotion ? 0 : 6)
                    .allowsHitTesting(phase == .off)
                    .accessibilityHidden(phase != .off)
                if phase == .turnedOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.accentGradient)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .onboardingSurface(cornerRadius: 24)
    }

    private var settingsButton: some View {
        Button(L10n("Settings")) {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        .font(.system(.subheadline, weight: .semibold))
        .buttonStyle(.bordered)
        .tint(OnboardingTheme.cyan)
    }

    private func update(for permission: NotificationPermissionState) {
        switch (phase, permission) {
        case (_, .denied):
            phase = .off
        case (.off, .authorized):
            phase = .turnedOn
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                if phase == .turnedOn { phase = .hidden }
            }
        default:
            break
        }
    }
}
