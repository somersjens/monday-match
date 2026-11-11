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
        let unanswered = ProfileAnswerSummary(value: "Not answered")
        switch step {
        case .dateOfBirth:
            guard let birthday = dateOfBirth, let date = birthday.date() else { return unanswered }
            let formatted = date.formatted(.dateTime.day().month(.wide).year())
            return ProfileAnswerSummary(value: formatted, detail: age(on: today).map { "\($0) years" })
        case .partnerAgeRange:
            guard let range = partnerAgeRange else { return unanswered }
            return ProfileAnswerSummary(value: "\(range.minimum)–\(range.maximum) years")
        case .height:
            return ProfileAnswerSummary(value: "\(heightCentimeters) cm")
        case .partnerHeightRange:
            let range = partnerHeightRange
            return ProfileAnswerSummary(value: range.isAny ? "Any height" : "\(range.minimum)–\(range.maximum) cm")
        case .gender:
            return gender.map { ProfileAnswerSummary(value: $0.title) } ?? unanswered
        case .partnerGenders:
            let titles = GenderIdentity.onboardingOptions.filter { partnerGenders.contains($0) }.map(\.title)
            return titles.isEmpty ? unanswered : ProfileAnswerSummary(value: titles.formatted(.list(type: .and)))
        case .sexualArrangement:
            let question = RelationshipPreferenceQuestion.sexualArrangement
            let selected = relationshipPreferences.selectedOptionIDs(for: question)
            let titles = question.options.filter { selected.contains($0.id) }.map(\.title)
            return titles.isEmpty ? unanswered : ProfileAnswerSummary(value: titles.joined(separator: ", "))
        case .languages:
            let names = languages.map { LanguageCatalog.option(for: $0).name }
            return names.isEmpty ? unanswered : ProfileAnswerSummary(value: names.formatted(.list(type: .and)))
        case .location:
            guard let location else { return unanswered }
            let place = location.placeName ?? (location.source == .device ? "Your current area" : "A place on the map")
            return ProfileAnswerSummary(value: place, detail: "within \(searchRadiusKilometers) km")
        case .hasChildren:
            return lifestyle.hasChildren.map { ProfileAnswerSummary(value: $0 ? "Yes" : "No") } ?? unanswered
        case .partnerHasChildren:
            return lifestyle.openToPartnerWithChildren.map { ProfileAnswerSummary(value: $0 ? "Yes" : "No") } ?? unanswered
        case .futureChildren:
            return lifestyle.futureChildren.map { ProfileAnswerSummary(value: $0.title) } ?? unanswered
        case .alcohol, .smoking, .drugs:
            guard let substance = step.substance else { return unanswered }
            let answer = lifestyle[substance]
            guard let own = answer.ownLevel else { return unanswered }
            return ProfileAnswerSummary(
                value: substance.levels[own],
                detail: answer.partnerMaximumLevel.map { "partner at most \(substance.levels[$0].lowercased())" }
            )
        case .aloneTime:
            let answer = lifestyle.aloneTime
            guard let own = answer.own else { return unanswered }
            let parts = [
                answer.partner.map { "partner: \($0)" },
                answer.importance.map { CompatibilityScaleAnswer.importanceTitle($0).lowercased() }
            ].compactMap { $0 }
            return ProfileAnswerSummary(value: "You: \(own)", detail: parts.isEmpty ? nil : parts.joined(separator: ", "))
        }
    }
}
