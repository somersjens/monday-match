import SwiftUI

/// The min/max question surface, with independent choices instead of a rail.
struct ReligionStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var answers: ReligionAnswers { viewModel.state.religion }
    private var phase: ReligionQuestionPhase { viewModel.state.religionPhase }
    private var selectedFill: LinearGradient {
        LinearGradient(colors: [OnboardingTheme.blue.opacity(0.24), OnboardingTheme.violet.opacity(0.16)],
                       startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                tab(.own, title: L10n("You"), value: answers.own?.title ?? L10n("Choose one"))
                tab(.partner, title: L10n("Partner"), value: partnerTabValue)
            }
            .padding(6)

            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 0.5)

            ForEach(Religion.allCases, id: \.self) { religion in
                row(religion)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onboardingSurface(cornerRadius: 24)
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .animation(OnboardingMotion.resolved(OnboardingMotion.selection, reduceMotion: reduceMotion), value: answers)
        .animation(OnboardingMotion.resolved(OnboardingMotion.selection, reduceMotion: reduceMotion), value: phase)
        .sensoryFeedback(.selection, trigger: answers)
    }

    private var partnerTabValue: String {
        let count = answers.acceptedPartnerReligions.count
        if count == Religion.allCases.count { return L10n("Open to all") }
        if count == 0 { return L10n("Open to all") }
        return L10n("\(count) selected")
    }

    private func tab(_ tabPhase: ReligionQuestionPhase, title: String, value: String) -> some View {
        let isActive = phase == tabPhase
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button { viewModel.setReligionPhase(tabPhase) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(isActive ? OnboardingTheme.primaryText : OnboardingTheme.secondaryText)
                Text(value)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(isActive ? OnboardingTheme.cyan : OnboardingTheme.secondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(isActive ? AnyShapeStyle(selectedFill) : AnyShapeStyle(Color.clear))
                    .overlay {
                        shape.strokeBorder(isActive ? AnyShapeStyle(OnboardingTheme.accentGradient) : AnyShapeStyle(Color.clear), lineWidth: 1.2)
                    }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ religion: Religion) {
        if phase == .own {
            viewModel.selectOwnReligion(religion)
        } else {
            viewModel.togglePartnerReligion(religion)
        }
    }

    private func row(_ religion: Religion) -> some View {
        let isOwn = answers.own == religion
        let isAccepted = answers.acceptedPartnerReligions.contains(religion)
        let isSelected = phase == .own ? isOwn : isAccepted
        return HStack(spacing: 0) {
            Button { select(religion) } label: {
                HStack(spacing: 14) {
                    OwnMarker(isSelected: isOwn, isActive: phase == .own)
                    Text(religion.title)
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(OnboardingTheme.primaryText.opacity(isSelected ? 1 : 0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(religion.title)
            .accessibilityValue(isSelected ? L10n("Selected") : L10n("Not selected"))
            .accessibilityHint(isSelected ? L10n("Tap to deselect.") : L10n("Tap to select."))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .overlay(alignment: .leading) {
                Button { viewModel.toggleOwnReligion(religion) } label: {
                    Color.clear
                        .frame(width: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: -11)
                .accessibilityLabel(L10n("You") + ", " + religion.title)
                .accessibilityAddTraits(isOwn ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("religion.own.\(religion.rawValue)")
            }

            if let explanation = religion.explanation {
                InfoPopoverButton(title: religion.title, message: explanation, isSuperscript: true)
            }

            Button { viewModel.togglePartnerReligion(religion) } label: {
                HStack(spacing: 0) {
                    Spacer(minLength: 14)
                    OwnMarker(isSelected: isAccepted, isActive: phase == .partner)
                }
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n("Partner") + ", " + religion.title)
            .accessibilityValue(isAccepted ? L10n("Selected") : L10n("Not selected"))
            .accessibilityAddTraits(isAccepted ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("religion.partner.\(religion.rawValue)")
        }
        .padding(.horizontal, 18)
        .background { selectedFill.opacity(isSelected ? 1 : 0) }
        .overlay(alignment: .bottom) {
            if religion != Religion.allCases.last {
                Rectangle()
                    .fill(.white.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.horizontal, 18)
            }
        }
    }
}
