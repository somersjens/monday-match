import SwiftUI

struct GenderStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let onAnswerSelected: () -> Void

    var body: some View {
        SelectionGroup(
            items: GenderIdentity.onboardingOptions,
            style: .single,
            title: \.title,
            isSelected: { viewModel.state.gender == $0 },
            onSelect: {
                viewModel.selectGender($0)
                onAnswerSelected()
            }
        )
    }
}

struct PartnerGendersStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let onAnswerSelected: () -> Void

    var body: some View {
        SelectionGroup(
            items: GenderIdentity.onboardingOptions,
            style: .multiple,
            title: \.title,
            isSelected: { viewModel.state.partnerGenders.contains($0) },
            onSelect: {
                viewModel.togglePartnerGender($0)
                onAnswerSelected()
            }
        )
    }
}

/// Renders any `RelationshipPreferenceQuestion`, single or multiple choice.
struct PreferenceQuestionStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let question: RelationshipPreferenceQuestion
    let onAnswerSelected: () -> Void

    var body: some View {
        let selected = viewModel.state.relationshipPreferences.selectedOptionIDs(for: question)
        SelectionGroup(
            items: question.options,
            style: question.selectionMode == .single ? .single : .multiple,
            title: \.title,
            isSelected: { selected.contains($0.id) },
            onSelect: {
                viewModel.selectPreference($0.id, in: question)
                onAnswerSelected()
            }
        )
    }
}
