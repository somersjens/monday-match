import SwiftUI

struct PartnerAgeRangeStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel

    var body: some View {
        let range = viewModel.partnerAgeRange

        VStack(spacing: 26) {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    number(range.minimum)
                    Text("–")
                        .font(.system(size: 44, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(OnboardingTheme.tertiaryText)
                    number(range.maximum)
                }
                Text("years old")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }
            .animation(.snappy(duration: 0.25), value: range)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("From \(range.minimum) to \(range.maximum) years old")

            VStack(spacing: 6) {
                DualRangeSlider(
                    lower: Binding(
                        get: { viewModel.partnerAgeRange.minimum },
                        set: { viewModel.updatePartnerAgeRange(minimum: $0, maximum: viewModel.partnerAgeRange.maximum) }
                    ),
                    upper: Binding(
                        get: { viewModel.partnerAgeRange.maximum },
                        set: { viewModel.updatePartnerAgeRange(minimum: viewModel.partnerAgeRange.minimum, maximum: $0) }
                    ),
                    bounds: PartnerAgeRules.bounds,
                    lowerLabel: "Youngest age",
                    upperLabel: "Oldest age",
                    unit: "years"
                )

                HStack {
                    Text(String(PartnerAgeRules.lowerBound))
                    Spacer()
                    Text(String(PartnerAgeRules.upperBound))
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
