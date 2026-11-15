import SwiftUI

/// Apple and Google sign-in, drawn in the onboarding style: two dark glass
/// controls with the providers' own marks. The control that is busy shows a
/// spinner in place of its mark; the other one steps back.
///
/// It is just its two buttons, so the parent stack spaces them and each can
/// carry its own transition.
struct AccountSignInButtons: View {
    @ObservedObject var viewModel: SignInViewModel
    var height: CGFloat = OnboardingTheme.buttonHeight
    var cornerRadius: CGFloat = 20
    /// Lets a parent stagger the two buttons in; nil shows them as they are.
    var arrival: ((Int) -> AnyTransition)?
    let onAuthenticated: (RestoredSession) -> Void

    var body: some View {
        Group {
            Button {
                viewModel.signInWithApple(onAuthenticated: onAuthenticated)
            } label: {
                AccountProviderLabel(title: L10n("Continue with Apple"),
                                     isBusy: viewModel.activeProvider == .apple) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 19, weight: .medium))
                        .offset(y: -1)
                }
            }
            .opacity(dimming(for: .apple))
            .accessibilityIdentifier("account.apple")
            .transition(arrival?(0) ?? .identity)

            Button {
                viewModel.signInWithGoogle(onAuthenticated: onAuthenticated)
            } label: {
                AccountProviderLabel(title: L10n("Continue with Google"),
                                     isBusy: viewModel.activeProvider == .google) {
                    Image("GoogleSignInLogo")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                }
            }
            .opacity(dimming(for: .google))
            .accessibilityIdentifier("account.google")
            .transition(arrival?(1) ?? .identity)
        }
        .buttonStyle(AccountProviderButtonStyle(height: height, cornerRadius: cornerRadius))
        .allowsHitTesting(!viewModel.isSigningIn)
        .animation(.easeInOut(duration: 0.2), value: viewModel.activeProvider)
    }

    private func dimming(for provider: SignInViewModel.Provider) -> Double {
        guard let active = viewModel.activeProvider else { return 1 }
        return active == provider ? 1 : 0.35
    }
}

private struct AccountProviderLabel<Mark: View>: View {
    let title: String
    let isBusy: Bool
    @ViewBuilder let mark: Mark

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                mark.opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        // Optically centred: the mark is balanced by the space after the title.
        .padding(.trailing, 8)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isBusy ? L10n("Signing in…") : "")
    }
}

private struct AccountProviderButtonStyle: ButtonStyle {
    let height: CGFloat
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: height)
            .background {
                shape.fill(Color(red: 0.035, green: 0.039, blue: 0.055).opacity(0.92))
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.10)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

/// A sign-in problem, resolved out of a soft blur under the buttons.
struct AccountSignInError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(OnboardingTheme.pink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LandingSwapEffect: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .scaleEffect(scale, anchor: .bottom)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// Landing controls trade places in a cascade: the leaving ones sink and
    /// lose focus, the arriving ones rise out of a blur one after another.
    static func landingSwap(index: Int, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity.animation(.easeInOut(duration: 0.2)) }
        let identity = LandingSwapEffect(offset: 0, blur: 0, scale: 1, opacity: 1)
        return .asymmetric(
            insertion: .modifier(active: LandingSwapEffect(offset: 22, blur: 10, scale: 0.97, opacity: 0),
                                 identity: identity)
                .animation(.spring(duration: 0.62, bounce: 0.14).delay(0.16 + Double(index) * 0.07)),
            removal: .modifier(active: LandingSwapEffect(offset: 14, blur: 8, scale: 0.97, opacity: 0),
                               identity: identity)
                .animation(.easeIn(duration: 0.2).delay(Double(index) * 0.04))
        )
    }
}
