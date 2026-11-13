import AuthenticationServices
import SwiftUI

struct SignInPlaceholderView: View {
    @StateObject private var viewModel: AppleSignInViewModel

    let onAuthenticated: (RestoredSession) -> Void

    init(
        authService: AuthServicing,
        onAuthenticated: @escaping (RestoredSession) -> Void
    ) {
        self.onAuthenticated = onAuthenticated
        _viewModel = StateObject(
            wrappedValue: AppleSignInViewModel(
                authService: authService
            )
        )
    }

    var body: some View {
        VStack(spacing: AppSpacing.xLarge) {
            Spacer()

            Image(systemName: "apple.logo")
                .font(.system(size: 56))
                .accessibilityHidden(true)

            VStack(spacing: AppSpacing.small) {
                Text(L10n("Create your account"))
                    .font(AppTypography.title)

                Text(
                    FirebaseBootstrap.isAvailable
                        ? L10n("Sign in securely with Apple. Firebase Authentication receives the Apple identity token and verified nonce.")
                        : L10n("Firebase is not installed yet, so this button currently uses the mock authentication service.")
                )
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryForeground)
                .multilineTextAlignment(.center)
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
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
            .disabled(viewModel.isSigningIn)
        }
        .padding(AppSpacing.large)
        .navigationTitle(L10n("Account"))
        .navigationBarTitleDisplayMode(.inline)
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
