import SwiftUI

/// The engine's in-app notices (a match that ended, a welcome back), shown at
/// the top of the screen and gone again after a few seconds.
struct NotificationNoticeBanner: View {
    @ObservedObject var engine: NotificationEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let visibleDuration: Duration = .seconds(7)

    var body: some View {
        VStack {
            if let notice = engine.notice {
                card(notice)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: engine.notice)
        .task(id: engine.notice?.id) {
            guard let notice = engine.notice else { return }
            AccessibilityNotification.Announcement(notice.title + " " + notice.body).post()
            try? await Task.sleep(for: Self.visibleDuration)
            if !Task.isCancelled, engine.notice?.id == notice.id { engine.notice = nil }
        }
    }

    private func card(_ notice: InAppNotice) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                engine.openNotice(notice)
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: notice.kind == .matchEnded ? "heart.slash" : "hand.wave")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [OnboardingTheme.cyan, OnboardingTheme.violet],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                        .background { RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.12)) }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(notice.title)
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.primaryText)
                        Text(notice.body)
                            .font(.footnote)
                            .foregroundStyle(OnboardingTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(notice.destination == nil)
            .accessibilityElement(children: .combine)

            Button { engine.notice = nil } label: {
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
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(OnboardingTheme.background.opacity(0.94))
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
