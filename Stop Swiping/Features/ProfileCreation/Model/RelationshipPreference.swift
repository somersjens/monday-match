import Foundation

/// A data-driven preference question. New relationship-preference questions
/// are added as values here and rendered by the same selection step.
struct RelationshipPreferenceQuestion: Identifiable, Hashable {
    enum SelectionMode: Hashable {
        case single
        case multiple
    }

    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
    }

    let id: String
    let prompt: String
    let selectionMode: SelectionMode
    let options: [Option]

    static var sexualArrangement: RelationshipPreferenceQuestion {
        RelationshipPreferenceQuestion(
            id: "sexualArrangement",
            prompt: L10n("What sexual arrangement are you comfortable with?"),
            selectionMode: .single,
            options: [
                Option(id: "partnerOnly", title: L10n("Only with my partner")),
                Option(id: "togetherWithOthers", title: L10n("Also together with other people")),
                Option(id: "separatelyFromPartner", title: L10n("Also separately from my partner")),
                Option(id: "noSex", title: L10n("No sex"))
            ]
        )
    }

    static var all: [RelationshipPreferenceQuestion] { [.sexualArrangement] }
}

/// Answers keyed by question ID, each holding the selected option IDs.
struct RelationshipPreferenceAnswers: Codable, Equatable {
    private(set) var selections: [String: [String]] = [:]

    func selectedOptionIDs(for question: RelationshipPreferenceQuestion) -> Set<String> {
        Set(selections[question.id] ?? [])
    }

    func isAnswered(_ question: RelationshipPreferenceQuestion) -> Bool {
        !(selections[question.id] ?? []).isEmpty
    }

    func shouldAutoAdvance(_ question: RelationshipPreferenceQuestion) -> Bool {
        let selected = selectedOptionIDs(for: question)
        switch question.selectionMode {
        case .single:
            return question.options.contains { selected.contains($0.id) }
        case .multiple:
            return !question.options.isEmpty && question.options.allSatisfy { selected.contains($0.id) }
        }
    }

    mutating func select(_ optionID: String, in question: RelationshipPreferenceQuestion) {
        guard question.options.contains(where: { $0.id == optionID }) else { return }
        switch question.selectionMode {
        case .single:
            selections[question.id] = [optionID]
        case .multiple:
            var current = selections[question.id] ?? []
            if let index = current.firstIndex(of: optionID) {
                current.remove(at: index)
            } else {
                current.append(optionID)
            }
            selections[question.id] = current.isEmpty ? nil : current
        }
    }
}
