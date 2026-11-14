import Combine
import SwiftUI

/// Profile codes that reach the app from outside, such as one scanned with
/// the iPhone's own camera. A profile waits here until the home screen can
/// show its match; nothing is saved, so it is gone when the app closes.
@MainActor
final class ProfileCodeInbox: ObservableObject {
    enum Notice: Equatable {
        /// Matching needs a finished profile on this phone too.
        case needsProfile(name: String)
        /// A profile code this build can't read, or one that isn't valid.
        case unreadable
    }

    @Published private(set) var pending: ProfileCreationState?
    @Published private(set) var notice: Notice?
    /// Changes with every notice, so the same one can be shown again.
    @Published private(set) var noticeCount = 0

    /// Takes in a link the app was opened with. Returns whether it was a
    /// profile code at all, readable or not.
    @discardableResult
    func open(_ url: URL, isProfileReady: Bool, today: CalendarDate = .today()) -> Bool {
        guard ProfileCode.isCode(url) else { return false }
        if let profile = ProfileCode.profile(from: url, today: today) {
            pending = profile
            show(isProfileReady ? nil : .needsProfile(name: profile.displayName))
        } else {
            show(.unreadable)
        }
        return true
    }

    /// Hands the waiting profile to whoever shows its match.
    func take() -> ProfileCreationState? {
        defer {
            pending = nil
            if case .needsProfile = notice { notice = nil }
        }
        return pending
    }

    func dismissNotice() { notice = nil }

    private func show(_ notice: Notice?) {
        self.notice = notice
        noticeCount += 1
    }
}

/// Says why a scanned code didn't open a match, from the top of the screen.
struct ProfileCodeNoticeBanner: View {
    @ObservedObject var inbox: ProfileCodeInbox
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let visibleDuration: Duration = .seconds(9)

    var body: some View {
        VStack {
            if let notice = inbox.notice {
                card(notice)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: inbox.notice)
        .task(id: inbox.noticeCount) {
            guard let notice = inbox.notice else { return }
            AccessibilityNotification.Announcement(Self.title(notice) + ". " + Self.message(notice)).post()
            try? await Task.sleep(for: Self.visibleDuration)
            if !Task.isCancelled { inbox.dismissNotice() }
        }
    }

    static func title(_ notice: ProfileCodeInbox.Notice) -> String {
        switch notice {
        case .needsProfile: L10n("Complete your profile first")
        case .unreadable: L10n("This code can’t be read")
        }
    }

    static func message(_ notice: ProfileCodeInbox.Notice) -> String {
        switch notice {
        case .needsProfile(let name):
            L10n("As soon as it’s finished, you’ll see whether you and \(name) are a match.")
        case .unreadable:
            L10n("Ask the other person to show their code again, or update the app.")
        }
    }

    private func card(_ notice: ProfileCodeInbox.Notice) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: notice == .unreadable ? "qrcode" : "person.crop.circle.badge.checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [OnboardingTheme.cyan, OnboardingTheme.violet],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.12))
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(Self.title(notice))
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(Self.message(notice))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button(action: inbox.dismissNotice) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n("Close"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(OnboardingTheme.background.opacity(0.94))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [OnboardingTheme.blue.opacity(0.30), OnboardingTheme.violet.opacity(0.20)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LinearGradient(colors: [OnboardingTheme.cyan.opacity(0.55), OnboardingTheme.violet.opacity(0.18)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
    }
}
