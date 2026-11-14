import SwiftUI

/// The other person's own answers, as they were when the profiles crossed.
struct MatchProfileView: View {
    let match: MatchSnapshot

    private var them: ProfileCreationState { match.them }
    private var day: CalendarDate { CalendarDate.today(calendar: BirthDateRules.calendar, now: match.matchedAt) }

    private static let basics: [ProfileCreationStep] = [
        .height, .gender, .partnerGenders, .sexualArrangement, .religion, .languages,
        .hasChildren, .partnerHasChildren, .futureChildren, .alcohol, .smoking, .drugs
    ]

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
                ForEach(CompatibilityScaleQuestion.sections, id: \.title) { group in
                    let answered = group.questions.filter { them.lifestyle[$0].own != nil }
                    if !answered.isEmpty {
                        section(group.title) {
                            ForEach(answered) { question in
                                scaleRow(question, value: them.lifestyle[question].own ?? 0,
                                         isLast: question.id == answered.last?.id)
                            }
                        }
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

    /// Age and distance come first; the birthday and exact place are never shared.
    private var facts: [(title: String, value: String)] {
        var facts: [(String, String)] = []
        if let age = them.age(on: day) {
            facts.append((L10n("Age"), L10n("\(age) years")))
        }
        if let place = them.location?.placeName, !place.isEmpty {
            facts.append((ProfileCreationStep.location.shortTitle, place))
        }
        if let distance = MatchReport.distanceKilometers(match.you.location, them.location) {
            facts.append((L10n("Distance"), L10n("About \(max(1, Int(distance.rounded()))) km away")))
        }
        for step in Self.basics {
            facts.append((step.shortTitle, them.summary(for: step, today: day).compact))
        }
        return facts
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(match.name)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(OnboardingTheme.primaryText)
            Text(L10n("\(match.name)’s own answers, as shared with you."))
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

    private func scaleRow(_ question: CompatibilityScaleQuestion, value: Int, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(question.title)
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.primaryText)
            HStack(spacing: 8) {
                Text(question.lowLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    ForEach(Array(CompatibilityScaleAnswer.range), id: \.self) { position in
                        Circle()
                            .fill(position == value ? AnyShapeStyle(OnboardingTheme.cyan)
                                                    : AnyShapeStyle(.white.opacity(0.14)))
                            .frame(width: position == value ? 9 : 6, height: position == value ? 9 : 6)
                    }
                }
                .frame(height: 10)
                Text(question.highLabel)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(OnboardingTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { if !isLast { separator } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(question.title)
        .accessibilityValue(L10n("\(value) of 5, from \(question.lowLabel) to \(question.highLabel)"))
    }

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }
}
