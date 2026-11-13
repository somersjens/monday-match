import SwiftUI

/// The landing page's night palette, shared by every onboarding surface.
enum OnboardingTheme {
    static let background = Color(red: 0.008, green: 0.012, blue: 0.035)
    static let cyan = Color(red: 0.20, green: 0.81, blue: 1)
    static let blue = Color(red: 0.16, green: 0.32, blue: 1)
    static let violet = Color(red: 0.61, green: 0.30, blue: 1)
    static let pink = Color(red: 0.95, green: 0.35, blue: 0.85)

    static let buttonGradient = LinearGradient(
        colors: [Color(red: 0.22, green: 0.42, blue: 0.94), Color(red: 0.40, green: 0.29, blue: 0.86)],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let accentGradient = LinearGradient(
        colors: [cyan, blue, violet],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.64)
    static let tertiaryText = Color.white.opacity(0.40)
    static let surface = Color.white.opacity(0.05)
    static let hairline = Color.white.opacity(0.10)

    static let contentWidth: CGFloat = 520
    static let controlWidth: CGFloat = 420
}

enum OnboardingMotion {
    static let step = Animation.spring(duration: 0.56, bounce: 0.1)
    static let stage = Animation.spring(duration: 0.95, bounce: 0.08)
    static let reveal = Animation.spring(duration: 0.45, bounce: 0.16)
    static let selection = Animation.spring(duration: 0.16, bounce: 0.12)
    /// How long navigation stays locked while a step transition plays.
    static let stepLock: Duration = .milliseconds(580)

    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }
}

enum StepDirection {
    case forward
    case backward
}

private struct StepTransitionEffect: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .scaleEffect(scale)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

private struct RevealEffect: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// Steps travel in the direction of navigation, losing focus as they leave.
    static func onboardingStep(_ direction: StepDirection, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let travel: CGFloat = direction == .forward ? 1 : -1
        return .asymmetric(
            insertion: .modifier(
                active: StepTransitionEffect(offset: 64 * travel, blur: 12, scale: 0.97, opacity: 0),
                identity: StepTransitionEffect(offset: 0, blur: 0, scale: 1, opacity: 1)
            ),
            removal: .modifier(
                active: StepTransitionEffect(offset: -44 * travel, blur: 12, scale: 0.97, opacity: 0),
                identity: StepTransitionEffect(offset: 0, blur: 0, scale: 1, opacity: 1)
            )
        )
    }

    /// Small elements resolve into place from a soft blur.
    static func onboardingReveal(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .modifier(
            active: RevealEffect(offset: 8, blur: 6, opacity: 0),
            identity: RevealEffect(offset: 0, blur: 0, opacity: 1)
        )
    }
}

/// The landing page's gradient button, shared by Get started and Continue so
/// the two read as one continuous control.
struct GlowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlowButtonBody(configuration: configuration)
    }
}

private struct GlowButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.5))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(OnboardingTheme.buttonGradient)
                    .saturation(isEnabled ? 1 : 0.2)
                    .opacity(isEnabled ? 1 : 0.4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(isEnabled ? 0.16 : 0.08), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.25), value: isEnabled)
    }
}

/// Quiet text button used for Back and secondary landing actions.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.5 : 0.82))
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
    }
}

extension View {
    /// A translucent panel that lets the ambient light show through.
    func onboardingSurface(cornerRadius: CGFloat = 26) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(OnboardingTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.14), .white.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
        }
    }
}
