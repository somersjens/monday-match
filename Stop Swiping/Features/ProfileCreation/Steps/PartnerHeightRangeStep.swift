import SwiftUI

struct PartnerHeightRangeStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel

    var body: some View {
        let range = viewModel.state.partnerHeightRange

        VStack(spacing: 26) {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    number(range.minimum)
                    Text("–")
                        .font(.system(size: 44, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(OnboardingTheme.tertiaryText)
                    number(range.maximum)
                }
                Text(range.isAny ? L10n("cm · any height") : "cm")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .contentTransition(.opacity)
            }
            .animation(.snappy(duration: 0.25), value: range)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(range.isAny ? L10n("Any height") : L10n("From \(range.minimum) to \(range.maximum) centimeters"))

            VStack(spacing: 6) {
                DualRangeSlider(
                    lower: Binding(
                        get: { viewModel.state.partnerHeightRange.minimum },
                        set: { viewModel.updatePartnerHeightRange(minimum: $0, maximum: viewModel.state.partnerHeightRange.maximum) }
                    ),
                    upper: Binding(
                        get: { viewModel.state.partnerHeightRange.maximum },
                        set: { viewModel.updatePartnerHeightRange(minimum: viewModel.state.partnerHeightRange.minimum, maximum: $0) }
                    ),
                    bounds: PartnerHeightRules.bounds,
                    lowerLabel: L10n("Shortest height"),
                    upperLabel: L10n("Tallest height"),
                    unit: "centimeters"
                )

                HStack {
                    Text(L10n("\(PartnerHeightRules.lowerBound) cm"))
                    Spacer()
                    Text(L10n("\(PartnerHeightRules.upperBound) cm"))
                }
                .font(.system(.footnote, design: .rounded).monospacedDigit())
                .foregroundStyle(OnboardingTheme.tertiaryText)
                .padding(.horizontal, 8)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 30)
        .onboardingSurface()
        .frame(maxWidth: OnboardingTheme.controlWidth)
    }

    private func number(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 64, weight: .light, design: .rounded).monospacedDigit())
            .foregroundStyle(OnboardingTheme.primaryText)
            .contentTransition(.numericText(value: Double(value)))
    }
}
