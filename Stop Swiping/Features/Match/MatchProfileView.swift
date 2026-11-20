import SwiftUI

/// What the other person shared that may be shown, as it was when the
/// profiles crossed. Their answers to single questions are never shown: the
/// scores show per category how well the two fit.
struct MatchProfileView: View {
    let match: MatchSnapshot

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header
                section(L10n("About \(match.name)")) {
                    let facts = facts
                    ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                        factRow(fact, isLast: index == facts.count - 1)
                    }
                }
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(OnboardingTheme.background)
    }

    private var facts: [MatchFact] { match.sharedFacts }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(match.name)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(OnboardingTheme.primaryText)
            Text(L10n("What \(match.name) shared with you. Answers to single questions stay private; the scores show per category how well you fit."))
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(.caption2, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(OnboardingTheme.tertiaryText)
                .padding(.horizontal, 16)
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0, content: rows)
                .onboardingSurface(cornerRadius: 20)
        }
    }

    private func factRow(_ fact: MatchFact, isLast: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(fact.title)
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.secondaryText)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(fact.value)
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.primaryText)
                // What they ask of a partner, on its own line.
                if let detail = fact.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                }
            }
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { if !isLast { separator } }
        .accessibilityElement(children: .combine)
    }

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }
}

/// One line in a match's card: the answer, and what they ask of a partner
/// below it.
struct MatchFact: Equatable {
    let title: String
    let value: String
    var detail: String? = nil

    /// Both parts as one text, a line each.
    var text: String { [value, detail].compactMap { $0 }.joined(separator: "\n") }
}

extension MatchSnapshot {
    private static let basics: [ProfileCreationStep] = [
        .height, .gender, .partnerGenders, .sexualArrangement, .religion, .languages,
        .hasChildren, .partnerHasChildren, .futureChildren, .alcohol, .smoking, .drugs
    ]

    /// The other person's basic answers. Age and distance come first; the
    /// birthday and exact place are never shared.
    var sharedFacts: [MatchFact] {
        let day = CalendarDate.today(calendar: BirthDateRules.calendar, now: matchedAt)
        var facts: [MatchFact] = []
        if let age = them.age(on: day) {
            facts.append(MatchFact(title: L10n("Age"), value: L10n("\(age) years")))
        }
        if let place = them.location?.placeName, !place.isEmpty {
            facts.append(MatchFact(title: ProfileCreationStep.location.shortTitle, value: place))
        }
        if let distance = distanceKilometers {
            facts.append(MatchFact(title: L10n("Distance"), value: L10n("About \(distance) km away")))
        }
        for step in Self.basics {
            let summary = them.summary(for: step, today: day)
            // On a line of its own, a detail starts like a sentence.
            let detail = summary.detail.map { $0.prefix(1).localizedUppercase + $0.dropFirst() }
            facts.append(MatchFact(title: Self.title(for: step), value: summary.value, detail: detail))
        }
        return facts
    }

    /// The overview's names, shorter where a long one crowds the answer.
    private static func title(for step: ProfileCreationStep) -> String {
        step == .religion ? L10n("Religion") : step.shortTitle
    }
}
