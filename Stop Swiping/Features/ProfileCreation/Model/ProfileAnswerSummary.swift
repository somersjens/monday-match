import Foundation

/// A readable version of one answer, for the profile overview.
struct ProfileAnswerSummary: Equatable {
    var value: String
    /// A second part of the answer, such as the limit set for a partner.
    var detail: String?

    var compact: String {
        [value, detail].compactMap { $0 }.joined(separator: " · ")
    }
}

extension ProfileCreationState {
    func summary(for step: ProfileCreationStep, today: CalendarDate) -> ProfileAnswerSummary {
        let unanswered = ProfileAnswerSummary(value: L10n("Not answered"))
        switch step {
        case .dateOfBirth:
            guard let birthday = dateOfBirth, let date = birthday.date() else { return unanswered }
            let formatted = date.formatted(.dateTime.day().month(.wide).year().locale(AppLocale.current))
            return ProfileAnswerSummary(value: formatted, detail: age(on: today).map { L10n("\($0) years") })
        case .partnerAgeRange:
            guard let range = partnerAgeRange else { return unanswered }
            return ProfileAnswerSummary(value: L10n("\(range.minimum)–\(range.maximum) years"))
        case .height:
            return ProfileAnswerSummary(value: L10n("\(heightCentimeters) cm"))
        case .partnerHeightRange:
            let range = partnerHeightRange
            return ProfileAnswerSummary(value: range.isAny ? L10n("Any height") : L10n("\(range.minimum)–\(range.maximum) cm"))
        case .gender:
            return gender.map { ProfileAnswerSummary(value: $0.title) } ?? unanswered
        case .partnerGenders:
            let titles = GenderIdentity.onboardingOptions.filter { partnerGenders.contains($0) }.map(\.title)
            return titles.isEmpty ? unanswered : ProfileAnswerSummary(value: titles.formatted(.list(type: .and).locale(AppLocale.current)))
        case .sexualArrangement:
            let question = RelationshipPreferenceQuestion.sexualArrangement
            let selected = relationshipPreferences.selectedOptionIDs(for: question)
            let titles = question.options.filter { selected.contains($0.id) }.map(\.title)
            return titles.isEmpty ? unanswered : ProfileAnswerSummary(value: titles.joined(separator: ", "))
        case .languages:
            let names = languages.map { LanguageCatalog.option(for: $0).name }
            return names.isEmpty ? unanswered : ProfileAnswerSummary(value: names.formatted(.list(type: .and).locale(AppLocale.current)))
        case .religion:
            return ProfileAnswerSummary(value: religion.ownSummary, detail: L10n("Partner: \(religion.partnerSummary)"))
        case .location:
            guard let location else { return unanswered }
            let place = location.placeName ?? (location.source == .device ? L10n("Your current area") : L10n("A place on the map"))
            return ProfileAnswerSummary(value: place, detail: L10n("within \(searchRadiusKilometers) km"))
        case .hasChildren:
            return lifestyle.hasChildren.map { ProfileAnswerSummary(value: $0 ? L10n("Yes") : L10n("No")) } ?? unanswered
        case .partnerHasChildren:
            return lifestyle.openToPartnerWithChildren.map { ProfileAnswerSummary(value: $0 ? L10n("Yes") : L10n("No")) } ?? unanswered
        case .futureChildren:
            return lifestyle.futureChildren.map { ProfileAnswerSummary(value: $0.title) } ?? unanswered
        case .alcohol, .smoking, .drugs:
            guard let substance = step.substance else { return unanswered }
            let answer = lifestyle[substance]
            guard let own = answer.ownLevel else { return unanswered }
            return ProfileAnswerSummary(
                value: substance.levels[own],
                detail: answer.partnerMaximumLevel.map { L10n("partner at most \(substance.levels[$0].lowercased())") }
            )
        case .aloneTime:
            let answer = lifestyle.aloneTime
            guard let own = answer.own else { return unanswered }
            let parts = [
                answer.partner.map { L10n("partner: \($0)") },
                answer.importance.map { CompatibilityScaleAnswer.importanceTitle($0).lowercased() }
            ].compactMap { $0 }
            return ProfileAnswerSummary(value: L10n("You: \(own)"), detail: parts.isEmpty ? nil : parts.joined(separator: ", "))
        }
    }
}
