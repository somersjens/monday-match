import AuthenticationServices
import SwiftUI

struct SignInPlaceholderView: View {
    @StateObject private var viewModel: SignInViewModel

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
        VStack(spacing: AppSpacing.large) {
            Spacer()

            Image(systemName: "person.crop.circle")
                .font(.system(size: 56))
                .foregroundStyle(OnboardingTheme.accentGradient)
                .accessibilityHidden(true)

            VStack(spacing: AppSpacing.small) {
                Text(L10n("Create your account"))
                    .font(AppTypography.title)

                Text(L10n("Sign in securely with Apple or Google. Your profile is backed up with Supabase so you can restore it on another device."))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.isSigningIn {
                ProgressView(L10n("Signing in…"))
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(
                    .continue,
                    onRequest: viewModel.configure,
                    onCompletion: {
                        viewModel.handle(
                            result: $0,
                            onAuthenticated: onAuthenticated
                        )
                    }
                )
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
                .disabled(viewModel.isSigningIn)

                Button {
                    viewModel.signInWithGoogle(onAuthenticated: onAuthenticated)
                } label: {
                    HStack(spacing: 12) {
                        Image("GoogleSignInLogo")
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                        Text(L10n("Continue with Google"))
                            .font(.system(size: 17, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.gray.opacity(0.4), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSigningIn)
                .opacity(viewModel.isSigningIn ? 0.5 : 1)
                .accessibilityIdentifier("account.google")
            }
        }
        .padding(AppSpacing.large)
        .navigationTitle(L10n("Account"))
        .navigationBarTitleDisplayMode(.inline)
        .background { OnboardingTheme.background.ignoresSafeArea() }
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
