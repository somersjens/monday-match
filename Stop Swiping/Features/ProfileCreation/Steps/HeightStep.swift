import SwiftUI

struct HeightStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel

    var body: some View {
        let centimeters = viewModel.state.heightCentimeters

        VStack(spacing: 24) {
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(centimeters)")
                        .font(.system(size: 64, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(OnboardingTheme.primaryText)
                        .contentTransition(.numericText(value: Double(centimeters)))
                    Text("cm")
                        .font(.system(.title3, weight: .medium))
                        .foregroundStyle(OnboardingTheme.secondaryText)
                }
                Text(HeightRules.imperialDescription(centimeters: centimeters))
                    .font(.system(.subheadline, design: .rounded).monospacedDigit())
                    .foregroundStyle(OnboardingTheme.tertiaryText)
            }
            .animation(.snappy(duration: 0.25), value: centimeters)
            .accessibilityHidden(true)

            HeightRuler(
                centimeters: Binding(
                    get: { viewModel.state.heightCentimeters },
                    set: { viewModel.updateHeight($0) }
                ),
                range: HeightRules.range
            )
        }
        .padding(.vertical, 28)
        .onboardingSurface()
        .frame(maxWidth: OnboardingTheme.controlWidth)
    }
}
