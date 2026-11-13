import SwiftUI

struct HeightStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            ZStack {
                if viewModel.state.hasAdjustedHeight {
                    HStack(spacing: 0) {
                        Text(L10n("No lies"))
                            .font(.system(.callout, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.primaryText.opacity(0.9))
                        InfoPopoverButton(
                            title: L10n("No lies"),
                            message: L10n("Providing false information may result in account termination. Purchases may not be restored, including benefits associated with the free new-user offer.")
                        )
                    }
                    .padding(.leading, 16)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.06))
                            .overlay { Capsule(style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1) }
                    }
                    .transition(.onboardingReveal(reduceMotion: reduceMotion))
                }
            }
            .frame(minHeight: 48)
            .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: viewModel.state.hasAdjustedHeight)
        }
        .padding(.vertical, 28)
        .onboardingSurface()
        .frame(maxWidth: OnboardingTheme.controlWidth)
    }
}
