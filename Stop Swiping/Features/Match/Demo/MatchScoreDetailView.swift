import SwiftUI

/// Which score the sheet explains: both ways together (the heart), or one of
/// the two directions (the numbers beside it).
enum MatchScoreDetail: String, Identifiable, Hashable {
    case together, yours, theirs

    var id: String { rawValue }

    init(_ perspective: MatchReport.Perspective) {
        self = perspective == .yours ? .yours : .theirs
    }
}

/// How a score came about, per category: how well the answers fit and how
/// much each category counts. Score × weight, added up, gives the total.
/// Single answers are never shown, so nobody can copy what the other looks for.
struct MatchScoreDetailView: View {
    let report: MatchReport
    /// Only the score that was tapped: no switching between them here.
    let mode: MatchScoreDetail
    let name: String

    private static let scoreColumn: CGFloat = 52
    private static let weightColumn: CGFloat = 60
    private static let rowInsets = EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 8)
    private static let scoreSize: CGFloat = 30
    private static let scoreCapHeight = UIFont.systemFont(ofSize: scoreSize, weight: .light).capHeight

    /// Follows Dynamic Type, like the title itself.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var titleCapHeight: CGFloat {
        UIFont.preferredFont(forTextStyle: .title2,
                             compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize)))
            .capHeight
    }

    private var categories: [MatchResult.CategoryFit] {
        switch mode {
        case .together: report.result.together
        case .yours: report.categories(.yours)
        case .theirs: report.categories(.theirs)
        }
    }

    private var total: Int {
        switch mode {
        case .together: report.average
        case .yours: report.score(.yours)
        case .theirs: report.score(.theirs)
        }
    }

    var body: some View {
        let categories = categories
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 16)
                if !categories.isEmpty {
                    VStack(spacing: 0) {
                        columnTitles
                        ForEach(categories) { category in
                            row(category, isLast: category.id == categories.last?.id)
                        }
                    }
                    // Room above the column titles and below the last line,
                    // so neither sits against the rounded edge.
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .onboardingSurface(cornerRadius: 20)
                    .padding(.bottom, 16)
                }
                Text(L10n("Each category weighs as much as its questions matter. Score × weight, added up, gives the total; rounding can make it differ by 1%."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                Text(L10n("Answers to single questions are never shown."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: OnboardingTheme.contentWidth)
            .padding(.horizontal, 20)
            .keepsSheetWidth()
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background { OnboardingTheme.background.ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(OnboardingTheme.background)
    }

    private var title: String {
        switch mode {
        case .together: L10n("You and \(name)")
        case .yours: L10n("Your match with \(name)")
        case .theirs: L10n("\(name)’s match with you")
        }
    }

    private var subtitle: String {
        switch mode {
        case .together: L10n("How well you and \(name) fit each other, both ways.")
        case .yours: L10n("How \(name)’s answers fit what you look for.")
        case .theirs: L10n("How your answers fit what \(name) looks for.")
        }
    }

    /// The title and the score line up on the top of their letters and
    /// digits, not on their baselines: the score is the larger of the two, so
    /// on a shared baseline it rose above the title.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .alignmentGuide(.top) { $0[.firstTextBaseline] - titleCapHeight }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(total, format: .percent)
                .font(.system(size: Self.scoreSize, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Self.fitColor(Double(total) / 100))
                .alignmentGuide(.top) { $0[.firstTextBaseline] - Self.scoreCapHeight }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var columnTitles: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            columnTitle(L10n("Score"), width: Self.scoreColumn)
            columnTitle(L10n("Weight"), width: Self.weightColumn)
        }
        .padding(.leading, Self.rowInsets.leading)
        .padding(.trailing, Self.rowInsets.trailing)
        .padding(.top, 10)
        .accessibilityHidden(true)
    }

    private func columnTitle(_ text: String, width: CGFloat) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(OnboardingTheme.tertiaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width)
    }

    private func row(_ category: MatchResult.CategoryFit, isLast: Bool) -> some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(category.category.title)
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(2)
                bar(category)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 10)
            Text(category.fitPercentage.map { L10nPercent($0) } ?? "–")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(category.fit.map { Self.fitColor($0) } ?? OnboardingTheme.tertiaryText)
                .frame(width: Self.scoreColumn)
            Text(L10nPercent(category.sharePercentage))
                .font(.system(.body, design: .rounded, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(category.share > 0 ? OnboardingTheme.secondaryText : OnboardingTheme.tertiaryText)
                .frame(width: Self.weightColumn)
        }
        .padding(Self.rowInsets)
        .overlay(alignment: .bottom) { divider(isLast: isLast) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.category.title)
        .accessibilityValue(category.fitPercentage.map {
            L10n("\($0) percent, weight \(category.sharePercentage) percent")
        } ?? L10n("Doesn’t count"))
    }

    /// How well it fits, as a filled line.
    private func bar(_ category: MatchResult.CategoryFit) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                if let fit = category.fit {
                    Capsule()
                        .fill(Self.fitColor(fit))
                        .frame(width: max(4, proxy.size.width * fit))
                }
            }
        }
        .frame(height: 4)
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

    /// Cyan for a good fit, through violet, to pink for a poor one. Scores
    /// bunch up high, so the scale spans where they actually fall: 95% and up
    /// is fully cyan, 65% and below fully pink.
    static func fitColor(_ fit: Double) -> Color {
        fitSpectrum((0.95 - fit) / 0.30)
    }

    /// Mixes cyan into pink; `amount` runs from 0 (a full fit) to 1 (no fit).
    static func fitSpectrum(_ amount: Double) -> Color {
        let near = (red: 0.20, green: 0.81, blue: 1.0)   // OnboardingTheme.cyan
        let far = (red: 0.95, green: 0.35, blue: 0.85)   // OnboardingTheme.pink
        let t = min(max(amount, 0), 1)
        return Color(red: near.red + (far.red - near.red) * t,
                     green: near.green + (far.green - near.green) * t,
                     blue: near.blue + (far.blue - near.blue) * t)
    }
}
