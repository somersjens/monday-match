import SwiftUI

/// An on/off switch in the onboarding palette. It reports taps instead of
/// owning its value, so turning it on can first ask for what it needs.
/// It clicks when its value actually changes, not on the tap, so a switch
/// that first opens a sheet stays quiet until it really slides.
struct GlowToggle: View {
    let isOn: Bool
    let label: String
    /// Off where the switch opens something that sounds its own opening.
    var playsSound = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(.white.opacity(0.10))
                Capsule()
                    .fill(OnboardingTheme.accentGradient)
                    .opacity(isOn ? 1 : 0)
                Capsule()
                    .strokeBorder(.white.opacity(isOn ? 0.32 : 0.14), lineWidth: 0.75)

                Circle()
                    .fill(.white)
                    .overlay {
                        Circle()
                            .fill(OnboardingTheme.accentGradient)
                            .frame(width: 8, height: 8)
                            .opacity(isOn ? 1 : 0)
                            .scaleEffect(isOn ? 1 : 0.3)
                    }
                    .frame(width: 26, height: 26)
                    .padding(3)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            }
            .frame(width: 54, height: 32)
            .shadow(color: OnboardingTheme.blue.opacity(isOn ? 0.75 : 0), radius: 12)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.38, bounce: 0.32), value: isOn)
            .frame(minWidth: 54, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn) { _, _ in playsSound }
        .soundFeedback(trigger: isOn) { _, on in playsSound ? (on ? .toggleOn : .toggleOff) : nil }
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? L10n("On") : L10n("Off"))
        .accessibilityAddTraits(.isToggle)
    }
}
