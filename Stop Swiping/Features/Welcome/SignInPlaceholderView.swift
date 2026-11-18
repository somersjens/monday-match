import SwiftUI

/// Sign-in as its own screen, for routes that can't open it in place on the
/// welcome screen. It uses the same night palette and controls.
struct SignInPlaceholderView: View {
    @StateObject private var viewModel: SignInViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onAuthenticated: (RestoredSession) -> Void

    init(
        authService: AuthServicing,
        onAuthenticated: @escaping (RestoredSession) -> Void
    ) {
        self.onAuthenticated = onAuthenticated
        _viewModel = StateObject(
            wrappedValue: SignInViewModel(
                authService: authService
            )
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Text(L10n("Create your account"))
                    .font(.system(.title, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text(L10n("Sign in securely with Apple or Google. Your profile is backed up with Supabase so you can restore it on another device."))
                    .font(.body)
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            AccountSignInButtons(viewModel: viewModel, onAuthenticated: onAuthenticated)

            if let message = viewModel.errorMessage {
                AccountSignInError(message: message)
                    .transition(.onboardingReveal(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 28)
        .controlsBottomPadding()
        .frame(maxWidth: .infinity)
        .adaptiveStageHeight()
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
        .navigationBarTitleDisplayMode(.inline)
        .background { OnboardingTheme.background.ignoresSafeArea() }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack {
        SignInPlaceholderView(
            authService: MockAuthService(),
            onAuthenticated: { _ in }
        )
    }
}
