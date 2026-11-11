import SwiftUI

/// The three children questions: plain filters, no scale or weighting.
struct ChildrenStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let step: ProfileCreationStep

    var body: some View {
        let answers = viewModel.state.lifestyle
        switch step {
        case .hasChildren:
            yesNo(selected: answers.hasChildren, onSelect: { viewModel.setHasChildren($0) })
        case .partnerHasChildren:
            yesNo(selected: answers.openToPartnerWithChildren, onSelect: { viewModel.setOpenToPartnerWithChildren($0) })
        default:
            SelectionGroup(
                items: FutureChildrenWish.allCases,
                style: .single,
                title: \.title,
                isSelected: { answers.futureChildren == $0 },
                onSelect: { viewModel.setFutureChildren($0) }
            )
        }
    }

    private func yesNo(selected: Bool?, onSelect: @escaping (Bool) -> Void) -> some View {
        SelectionGroup(
            items: [true, false],
            style: .single,
            title: { $0 ? "Yes" : "No" },
            isSelected: { selected == $0 },
            onSelect: onSelect
        )
    }
}

/// How often the user does something, and how often a partner may at most,
/// answered on one scale.
struct SubstanceStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let substance: Substance

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: SubstanceScale.Mode

    init(viewModel: ProfileCreationViewModel, substance: Substance) {
        self.viewModel = viewModel
        self.substance = substance
        let answer = viewModel.state.lifestyle[substance]
        _mode = State(initialValue: answer.ownLevel != nil && answer.partnerMaximumLevel == nil ? .partner : .own)
    }

    var body: some View {
        let answer = viewModel.state.lifestyle[substance]
        SubstanceScale(
            levels: substance.levels,
            ownLevel: answer.ownLevel,
            partnerMaximum: answer.partnerMaximumLevel,
            mode: $mode,
            onSelectOwn: selectOwn,
            onSelectPartnerMaximum: { viewModel.setPartnerMaximumLevel($0, for: substance) }
        )
    }

    /// The first own answer moves on to the partner limit by itself.
    private func selectOwn(_ level: Int) {
        let needsLimit = viewModel.state.lifestyle[substance].partnerMaximumLevel == nil
        viewModel.setOwnLevel(level, for: substance)
        guard needsLimit else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 380))
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion)) {
                mode = .partner
            }
        }
    }
}

/// A compatibility question: the user's position, the partner they look for,
/// and how much a match on it matters.
struct CompatibilityScaleStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let question: CompatibilityScaleQuestion

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let answer = viewModel.state.lifestyle.aloneTime
        VStack(spacing: 12) {
            card(title: "How are you usually?") {
                ScaleSelector(
                    label: "How are you usually?",
                    value: answer.own,
                    lowLabel: question.lowLabel,
                    highLabel: question.highLabel,
                    valueDescription: { positionDescription($0) },
                    onSelect: { viewModel.setAloneTimeOwn($0) }
                )
            }

            card(
                title: "What suits your ideal partner best?",
                note: answer.own != nil && !answer.isPartnerCustomized ? "Set to your own answer. Adjust it if you like." : nil
            ) {
                ScaleSelector(
                    label: "What suits your ideal partner best?",
                    value: answer.partner,
                    lowLabel: question.lowLabel,
                    highLabel: question.highLabel,
                    valueDescription: { positionDescription($0) },
                    onSelect: { viewModel.setAloneTimePartner($0) }
                )
            }

            card(
                title: "How important is a good match on this?",
                value: answer.importance.map { CompatibilityScaleAnswer.importanceTitle($0) }
            ) {
                ScaleSelector(
                    label: "How important is a good match on this?",
                    value: answer.importance,
                    lowLabel: "Not important",
                    highLabel: "Very important",
                    valueDescription: { "\($0), \(CompatibilityScaleAnswer.importanceTitle($0))" },
                    onSelect: { viewModel.setAloneTimeImportance($0) }
                )
            }
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: answer)
    }

    private func positionDescription(_ value: Int) -> String {
        switch value {
        case 1: "1, \(question.lowLabel.lowercased())"
        case 3: "3, right in the middle"
        case 5: "5, \(question.highLabel.lowercased())"
        default: "\(value) of 5"
        }
    }

    private func card<Content: View>(
        title: String,
        value: String? = nil,
        note: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.cyan)
                        .contentTransition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHidden(true)

            content()

            if let note {
                Label(note, systemImage: "arrow.turn.down.right")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(OnboardingTheme.tertiaryText)
                    .transition(.onboardingReveal(reduceMotion: reduceMotion))
            }
        }
        .padding(18)
        .onboardingSurface(cornerRadius: 24)
    }
}
