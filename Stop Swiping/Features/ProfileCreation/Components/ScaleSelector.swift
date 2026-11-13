import SwiftUI

/// Five points on a line, for 1–5 answers where 3 is a true midpoint.
struct ScaleSelector: View {
    let label: String
    let value: Int?
    var lowLabel: String?
    var highLabel: String?
    /// Mirrored partner selections can follow the user's immediate highlight.
    var selectionAnimation: Animation? = nil
    let valueDescription: (Int) -> String
    let onSelect: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let range = CompatibilityScaleAnswer.range

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Capsule()
                    .fill(.white.opacity(0.10))
                    .frame(height: 2)
                    .padding(.horizontal, 22)

                HStack(spacing: 0) {
                    ForEach(Array(range), id: \.self) { point in
                        Button { onSelect(point) } label: { pointView(point) }
                            .buttonStyle(ScalePointPressStyle())
                        if point < range.upperBound { Spacer(minLength: 4) }
                    }
                }
            }

            if let lowLabel, let highLabel {
                HStack(alignment: .top) {
                    Text(lowLabel)
                    Spacer(minLength: 12)
                    Text(highLabel)
                        .multilineTextAlignment(.trailing)
                }
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(OnboardingTheme.secondaryText)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.map(valueDescription) ?? L10n("Not answered"))
        .accessibilityAdjustableAction { direction in
            let current = value ?? 3
            switch direction {
            case .increment: onSelect(min(current + (value == nil ? 0 : 1), range.upperBound))
            case .decrement: onSelect(max(current - (value == nil ? 0 : 1), range.lowerBound))
            @unknown default: break
            }
        }
    }

    private func pointView(_ point: Int) -> some View {
        let isSelected = point == value
        return Text("\(point)")
            .font(.system(.body, design: .rounded, weight: .semibold).monospacedDigit())
            .foregroundStyle(isSelected ? .white : OnboardingTheme.secondaryText)
            .frame(width: 44, height: 44)
            .background {
                Circle()
                    .fill(Color(red: 0.07, green: 0.08, blue: 0.13))
                    .overlay {
                        Circle().fill(OnboardingTheme.accentGradient)
                            .opacity(isSelected ? 1 : 0)
                            .scaleEffect(isSelected ? 1 : 0.5)
                    }
                    .overlay {
                        Circle().strokeBorder(.white.opacity(isSelected ? 0.25 : 0.14), lineWidth: 1)
                    }
            }
            .shadow(color: OnboardingTheme.blue.opacity(isSelected ? 0.6 : 0), radius: 12, y: 3)
            .animation(selectionAnimation, value: value)
            // Direct selections change color immediately; only their lift animates.
            .animation(selectionAnimation ?? OnboardingMotion.resolved(OnboardingMotion.selection, reduceMotion: reduceMotion)) { point in
                point.scaleEffect(isSelected ? 1.08 : 1)
            }
            .contentShape(Circle())
    }
}

private struct ScalePointPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // The release animation must not delay the selection color as well.
            .animation(.spring(duration: 0.22, bounce: 0.3)) { label in
                label.scaleEffect(configuration.isPressed ? 0.92 : 1)
            }
    }
}
