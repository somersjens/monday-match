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
    /// This page's own copy of the shared mode. The view model resets the
    /// mode for the next substance while this page is still leaving, and
    /// the leaving page must not flip back to its own side on the way out.
    @State private var mode: PartnerPreferenceScale.Mode

    init(viewModel: ProfileCreationViewModel, substance: Substance) {
        self.viewModel = viewModel
        self.substance = substance
        _mode = State(initialValue: viewModel.substanceMode)
    }

    private var isCurrent: Bool { viewModel.currentStep.substance == substance }

    var body: some View {
        let answer = viewModel.state.lifestyle[substance]
        PartnerPreferenceScale(
            levels: substance.levels,
            ownIndex: answer.ownLevel,
            partnerLimitIndex: answer.partnerMaximumLevel,
            mode: Binding(
                get: { mode },
                set: { newMode in
                    mode = newMode
                    if isCurrent { viewModel.substanceMode = newMode }
                }
            ),
            onSelectOwn: selectOwn,
            onSelectPartnerLimit: { viewModel.setPartnerMaximumLevel($0, for: substance) }
        )
        .onChange(of: viewModel.substanceMode) { _, newMode in
            if isCurrent { mode = newMode }
        }
    }

    /// The first own answer moves on to the partner limit by itself.
    private func selectOwn(_ level: Int) {
        let needsLimit = viewModel.substanceMode == .own
            && viewModel.state.lifestyle[substance].partnerMaximumLevel == nil
        viewModel.setOwnLevel(level, for: substance)
        guard needsLimit else { return }
        Task {
            try? await Task.sleep(for: reduceMotion ? .zero : OnboardingMotion.partnerHandoff)
            guard viewModel.currentStep.substance == substance,
                  viewModel.substanceMode == .own,
                  viewModel.state.lifestyle[substance].partnerMaximumLevel == nil else { return }
            // The scale animates its own ring handoff.
            viewModel.substanceMode = .partner
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
                        ? .easeOut(duration: 0.14).delay(0.06) : nil,
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
