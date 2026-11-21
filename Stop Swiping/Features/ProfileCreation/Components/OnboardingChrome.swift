import SwiftUI

/// The round gradient checkmark at the top right of the profile overview and
/// of a question being changed from it.
struct RoundCheckmarkButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accentGradient)
                .frame(width: 44, height: 44)
                .background { Circle().fill(.white.opacity(0.08)) }
                .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct OnboardingStepHeader: View {
    let title: String
    let subtitle: String?
    var titleFocus: AccessibilityFocusState<Bool>.Binding
    /// Keeps the title clear of a button floating at its top right.
    var titleTrailingInset: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // At most two lines, so every question starts at the same
            // height; a longer one shrinks a little rather than wrapping.
            // Accessibility sizes keep wrapping instead of shrinking.
            Text(title)
                .font(.system(.title, design: .default, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(OnboardingTheme.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(titleFocus)
                .padding(.trailing, titleTrailingInset)

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

/// A calm note just above Continue: centred text in a light grey frame.
struct OnboardingNoticeLabel: View {
    let text: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Text(text)
            .font(.system(.footnote, weight: .medium))
            .foregroundStyle(OnboardingTheme.primaryText.opacity(0.9))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                shape
                    .fill(.white.opacity(0.05))
                    .overlay { shape.strokeBorder(.white.opacity(0.28), lineWidth: 1) }
            }
            .contentTransition(.opacity)
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
