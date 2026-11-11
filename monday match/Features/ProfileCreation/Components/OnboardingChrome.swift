import SwiftUI

/// Progress as a row of points of light; the current step stretches into a
/// short gradient bar rather than filling a conventional progress bar.
struct OnboardingProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { index in
                Capsule()
                    .fill(fill(for: index))
                    .frame(width: index == current ? 22 : 6, height: 6)
            }
        }
        .animation(OnboardingMotion.step, value: current)
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of \(total)")
    }

    private func fill(for index: Int) -> AnyShapeStyle {
        if index == current { return AnyShapeStyle(OnboardingTheme.accentGradient) }
        return AnyShapeStyle(Color.white.opacity(index < current ? 0.55 : 0.16))
    }
}

struct OnboardingStepHeader: View {
    let title: String
    let subtitle: String?
    var titleFocus: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.title, design: .default, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(OnboardingTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(titleFocus)

            if let subtitle {
                Text(subtitle)
                    .font(.system(.body))
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Inline, non-blocking feedback that resolves out of a soft blur.
struct OnboardingFeedbackLabel: View {
    let feedback: ProfileCreationFeedback

    var body: some View {
        Label {
            Text(feedback.message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: feedback.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(OnboardingTheme.cyan)
        }
        .font(.system(.callout, weight: .medium))
        .foregroundStyle(OnboardingTheme.primaryText.opacity(0.9))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay { Capsule(style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1) }
        }
    }
}

/// Horizontal shake used when a submission is rejected.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 7
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 4), y: 0))
    }
}
