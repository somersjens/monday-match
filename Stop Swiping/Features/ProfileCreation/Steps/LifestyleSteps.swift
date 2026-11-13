import SwiftUI

/// The three children questions: plain filters, no scale or weighting.
struct ChildrenStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let step: ProfileCreationStep
    let onAnswerSelected: () -> Void

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
                onSelect: {
                    viewModel.setFutureChildren($0)
                    onAnswerSelected()
                }
            )
        }
    }

    private func yesNo(selected: Bool?, onSelect: @escaping (Bool) -> Void) -> some View {
        SelectionGroup(
            items: [true, false],
            style: .single,
            title: { $0 ? L10n("Yes") : L10n("No") },
            isSelected: { selected == $0 },
            onSelect: {
                onSelect($0)
                onAnswerSelected()
            }
        )
    }
}

/// How often the user does something, and how often a partner may at most,
/// answered on one scale.
struct SubstanceStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let substance: Substance

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let answer = viewModel.state.lifestyle[substance]
        PartnerPreferenceScale(
            levels: substance.levels,
            ownIndex: answer.ownLevel,
            partnerLimitIndex: answer.partnerMaximumLevel,
            mode: $viewModel.substanceMode,
            onSelectOwn: selectOwn,
            onSelectPartnerLimit: { viewModel.setPartnerMaximumLevel($0, for: substance) }
        )
    }

    /// The first own answer moves on to the partner limit by itself.
    private func selectOwn(_ level: Int) {
        let needsLimit = viewModel.substanceMode == .own
            && viewModel.state.lifestyle[substance].partnerMaximumLevel == nil
        viewModel.setOwnLevel(level, for: substance)
        guard needsLimit else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 380))
            guard viewModel.currentStep.substance == substance,
                  viewModel.substanceMode == .own,
                  viewModel.state.lifestyle[substance].partnerMaximumLevel == nil else { return }
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion)) {
                viewModel.substanceMode = .partner
            }
        }
    }
}

/// A compatibility question: the user's position, the partner they look for,
/// and how much a match on it matters.
struct CompatibilityScaleStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let question: CompatibilityScaleQuestion
    let onAnswerSelected: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let answer = viewModel.state.lifestyle[question]
        VStack(spacing: 12) {
            card(title: L10n("What describes you best?")) {
                ScaleSelector(
                    label: L10n("What describes you best?"),
                    value: answer.own,
                    lowLabel: question.lowLabel,
                    highLabel: question.highLabel,
                    valueDescription: { positionDescription($0) },
                    onSelect: {
                        viewModel.setCompatibilityOwn($0, for: question)
                        onAnswerSelected()
                    }
                )
            }

            card(title: L10n("What suits your ideal partner best?")) {
                ScaleSelector(
                    label: L10n("What suits your ideal partner best?"),
                    value: answer.partner,
                    lowLabel: question.lowLabel,
                    highLabel: question.highLabel,
                    // Show the tapped own answer first; its mirrored value follows.
                    selectionAnimation: !answer.isPartnerCustomized && !reduceMotion
                        ? .easeOut(duration: 0.16).delay(0.12) : nil,
                    valueDescription: { positionDescription($0) },
                    onSelect: {
                        viewModel.setCompatibilityPartner($0, for: question)
                        onAnswerSelected()
                    }
                )
            }

            card(title: L10n("How important is a good match on this?")) {
                ScaleSelector(
                    label: L10n("How important is a good match on this?"),
                    value: answer.importance,
                    lowLabel: L10n("Not important"),
                    highLabel: L10n("Very important"),
                    valueDescription: { "\($0), \(CompatibilityScaleAnswer.importanceTitle($0))" },
                    onSelect: {
                        viewModel.setCompatibilityImportance($0, for: question)
                        onAnswerSelected()
                    }
                )
            }
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
    }

    private func positionDescription(_ value: Int) -> String {
        switch value {
        case 1: "1, \(question.lowLabel.lowercased())"
        case 3: L10n("3, right in the middle")
        case 5: "5, \(question.highLabel.lowercased())"
        default: L10n("\(value) of 5")
        }
    }

    private func card<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(OnboardingTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)

            content()
        }
        .padding(18)
        .onboardingSurface(cornerRadius: 24)
    }
}
