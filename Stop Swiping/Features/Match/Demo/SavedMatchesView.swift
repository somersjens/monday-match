import SwiftUI

/// Every saved match, newest first. Opening one replays its match screen.
struct SavedMatchesView: View {
    @ObservedObject var store: SavedMatchStore
    let onOpen: (MatchSnapshot) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                if store.matches.isEmpty {
                    Text(L10n("No saved matches yet."))
                        .font(.subheadline)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .onboardingSurface(cornerRadius: 22)
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.matches) { match in
                            row(match, isLast: match.id == store.matches.last?.id)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .onboardingSurface(cornerRadius: 24)
                }
            }
            .frame(maxWidth: OnboardingTheme.contentWidth)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background { OnboardingTheme.background.ignoresSafeArea() }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("Saved matches"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(L10n("Scores are kept as they were on the day you matched."))
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accentGradient)
                    .frame(width: 44, height: 44)
                    .background { Circle().fill(.white.opacity(0.08)) }
                    .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n("Close"))
        }
        .padding(.top, 12)
    }

    private func row(_ match: MatchSnapshot, isLast: Bool) -> some View {
        let report = match.report
        let date = match.matchedAt.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(AppLocale.current))
        return Button { onOpen(match) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(match.name)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                    Text(date)
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(report.average)%")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(OnboardingTheme.cyan)
                    Text(report.isMatch ? L10n("Match") : L10n("No match"))
                        .font(.caption2)
                        .foregroundStyle(report.isMatch ? OnboardingTheme.secondaryText : OnboardingTheme.pink)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(SavedMatchRowStyle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.leading, 16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(match.name)
        .accessibilityValue(report.isMatch
            ? L10n("\(date), \(report.average) percent, a match")
            : L10n("\(date), \(report.average) percent, no match"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct SavedMatchRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.08 : 0))
    }
}
