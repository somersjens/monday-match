import SwiftUI

/// My matches, newest first: matches saved from a code exchange and every
/// automatic match that was broken. Opening one replays its match screen; a
/// broken one shows its conversation there.
struct SavedMatchesView: View {
    @ObservedObject var store: SavedMatchStore
    @ObservedObject var center: LiveMatchCenter
    let onOpen: (MatchSnapshot) -> Void
    var onOpenBroken: (CloudChatMatch) -> Void = { _ in }

    private enum Entry: Identifiable {
        case saved(MatchSnapshot)
        case broken(CloudChatMatch)
        var id: UUID {
            switch self {
            case .saved(let match): match.id
            case .broken(let match): match.id
            }
        }
        var date: Date {
            switch self {
            case .saved(let match): match.matchedAt
            case .broken(let match): match.matchedAt ?? match.endedAt ?? .distantPast
            }
        }
    }

    private var entries: [Entry] {
        let saved = store.matches.map(Entry.saved)
        let saveIDs = Set(store.matches.map(\.id))
        let broken = center.pastMatches.filter { !saveIDs.contains($0.id) }.map(Entry.broken)
        return (saved + broken).sorted { $0.date > $1.date }
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                if entries.isEmpty {
                    Text(L10n("No matches yet."))
                        .font(.subheadline)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .onboardingSurface(cornerRadius: 22)
                } else {
                    let entries = entries
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            let isLast = entry.id == entries.last?.id
                            switch entry {
                            case .saved(let match): row(match, isLast: isLast)
                            case .broken(let match): brokenRow(match, isLast: isLast)
                            }
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
        HStack(alignment: .headerTitle, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("My matches"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .headerTitleGuide()
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
                    Text(report.average, format: .percent)
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

extension SavedMatchesView {
    /// A broken automatic match: still opens, with "Match" struck through.
    fileprivate func brokenRow(_ match: CloudChatMatch, isLast: Bool) -> some View {
        let name = center.displayName(for: match)
        let date = (match.matchedAt ?? Date()).formatted(.dateTime.day().month(.wide).year().locale(AppLocale.current))
        return Button { onOpenBroken(match) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText.opacity(0.75))
                    Text(date)
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(match.average, format: .percent)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(OnboardingTheme.cyan.opacity(0.55))
                    Text(L10n("Match"))
                        .font(.caption2)
                        .strikethrough(true, color: OnboardingTheme.pink)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                    Text(L10n("No longer active"))
                        .font(.caption2)
                        .foregroundStyle(OnboardingTheme.pink)
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
        .accessibilityLabel(name)
        .accessibilityValue(L10n("\(date), \(match.average) percent, a match that is no longer active"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("matches.broken")
    }
}

private struct SavedMatchRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.08 : 0))
    }
}
