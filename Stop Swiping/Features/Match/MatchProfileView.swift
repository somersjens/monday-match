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
                        factRow(title: fact.title, value: fact.value, isLast: index == facts.count - 1)
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

    private var facts: [(title: String, value: String)] { match.sharedFacts }

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

    private func factRow(title: String, value: String, isLast: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.primaryText)
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

extension MatchSnapshot {
    private static let basics: [ProfileCreationStep] = [
        .height, .gender, .partnerGenders, .sexualArrangement, .religion, .languages,
        .hasChildren, .partnerHasChildren, .futureChildren, .alcohol, .smoking, .drugs
    ]

    /// The other person's basic answers. Age and distance come first; the
    /// birthday and exact place are never shared.
    var sharedFacts: [(title: String, value: String)] {
        let day = CalendarDate.today(calendar: BirthDateRules.calendar, now: matchedAt)
        var facts: [(String, String)] = []
        if let age = them.age(on: day) {
            facts.append((L10n("Age"), L10n("\(age) years")))
        }
        if let place = them.location?.placeName, !place.isEmpty {
            facts.append((ProfileCreationStep.location.shortTitle, place))
        }
        if let distance = distanceKilometers {
            facts.append((L10n("Distance"), L10n("About \(distance) km away")))
        }
        for step in Self.basics {
            facts.append((step.shortTitle, them.summary(for: step, today: day).compact))
        }
        return facts
    }
}
