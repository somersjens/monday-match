import SwiftUI

/// The answers behind one score, compact: per question the other person's
/// answer, the answer that was looked for, and how much it matters.
struct MatchScoreDetailView: View {
    let report: MatchReport
    let perspective: MatchReport.Perspective
    let name: String

    private static let columnWidth: CGFloat = 54
    /// The number columns carry their own side room, so the trailing inset is
    /// smaller: the last digit then sits about as far in as the titles do.
    private static let sectionGap: CGFloat = 20
    private static let rowInsets = EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 4)

    /// How far an answer sits from the one that was looked for.
    private enum Fit {
        case exact, near, far

        var color: Color {
            switch self {
            case .exact: OnboardingTheme.cyan
            case .near: OnboardingTheme.primaryText
            case .far: OnboardingTheme.pink
            }
        }
    }

    private func fit(_ row: MatchReport.Row) -> Fit {
        let gap = abs(row.value - row.wanted)
        if gap == 0 { return .exact }
        // A gap on an answer that doesn't count costs nothing, so it isn't flagged.
        return gap >= 2 && row.weight > 0 ? .far : .near
    }

    private var rows: [ProfileCreationStep: MatchReport.Row] {
        Dictionary(uniqueKeysWithValues: report.rows(perspective).map { ($0.step, $0) })
    }

    var body: some View {
        let rows = rows
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                header
                    .padding(.bottom, 14)
                ForEach(CompatibilityScaleQuestion.sections, id: \.title) { section in
                    let answered = section.questions.compactMap { rows[$0.step] }
                    if !answered.isEmpty {
                        Section {
                            VStack(spacing: 0) {
                                ForEach(answered) { row in
                                    rowView(row, isLast: row.id == answered.last?.id)
                                }
                            }
                            .onboardingSurface(cornerRadius: 20)
                            .padding(.bottom, Self.sectionGap)
                        } header: {
                            sectionHeader(section.title)
                        }
                    }
                }
                Text(L10n("Each answer counts by its importance: every step up counts double, and 1 doesn’t count at all."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: OnboardingTheme.contentWidth)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background { OnboardingTheme.background.ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(OnboardingTheme.background)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(perspective == .yours ? L10n("Your match with \(name)") : L10n("\(name)’s match with you"))
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(perspective == .yours
                     ? L10n("How \(name)’s answers fit what you look for.")
                     : L10n("How your answers fit what \(name) looks for."))
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("\(report.score(perspective))%")
                .font(.system(size: 30, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(OnboardingTheme.cyan)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Pinned, so the column names stay readable while scrolling.
    private func sectionHeader(_ title: String) -> some View {
        let subject = perspective == .yours ? name : L10n("You")
        return HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(title.uppercased())
                .font(.system(.caption2, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(OnboardingTheme.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isHeader)
            columnTitle(subject)
            columnTitle(L10n("Wanted"))
            columnTitle(L10n("Importance"))
        }
        .padding(.leading, Self.rowInsets.leading)
        .padding(.trailing, Self.rowInsets.trailing)
        .padding(.vertical, 8)
        .background(OnboardingTheme.background.opacity(0.94))
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(OnboardingTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: Self.columnWidth)
            .accessibilityHidden(true)
    }

    private func rowView(_ row: MatchReport.Row, isLast: Bool) -> some View {
        HStack(spacing: 0) {
            Text(row.step.compatibilityQuestion?.title ?? row.step.shortTitle)
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.primaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            number(row.value, color: fit(row).color, weight: .semibold)
            number(row.wanted, color: OnboardingTheme.secondaryText)
            importance(row)
        }
        .padding(Self.rowInsets)
        .overlay(alignment: .bottom) { divider(isLast: isLast) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.step.compatibilityQuestion?.title ?? row.step.shortTitle)
        .accessibilityValue(perspective == .yours
            ? L10n("\(name): \(row.value), wanted: \(row.wanted), importance: \(row.importance) of 5")
            : L10n("You: \(row.value), \(name) wants: \(row.wanted), importance: \(row.importance) of 5"))
    }

    @ViewBuilder
    private func divider(isLast: Bool) -> some View {
        if !isLast {
            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.leading, 16)
        }
    }

    /// Neutral: it says how much an answer counts, not how well it fits.
    /// Dimmer still at 1, where the answer doesn't count at all.
    private func importance(_ row: MatchReport.Row) -> some View {
        number(row.importance, color: row.weight > 0 ? OnboardingTheme.secondaryText : OnboardingTheme.tertiaryText)
    }

    private func number(_ value: Int, color: Color, weight: Font.Weight = .medium) -> some View {
        Text("\(value)")
            .font(.system(.body, design: .rounded, weight: weight))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: Self.columnWidth)
    }
}
