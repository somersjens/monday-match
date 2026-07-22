import SwiftUI

struct WelcomeView: View {
    let onGetStarted: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()

            WelcomeBackgroundDecoration()

            VStack(spacing: AppSpacing.xLarge) {
                Spacer(minLength: AppSpacing.xxLarge)

                WelcomeMarkView()

                VStack(spacing: AppSpacing.medium) {
                    Text("One thoughtful match.")
                        .font(AppTypography.hero)
                        .multilineTextAlignment(.center)

                    Text(
                        "No endless swiping. Join the weekly round and meet someone selected for real compatibility."
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                }

                Spacer()

                VStack(spacing: AppSpacing.medium) {
                    PrimaryButton(
                        title: "Get started",
                        action: onGetStarted
                    )

                    Button("I already have an account", action: onSignIn)
                        .font(AppTypography.body.weight(.semibold))
                        .foregroundStyle(AppColors.foreground)
                        .frame(minHeight: 44)
                }
            }
            .padding(AppSpacing.large)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct WelcomeBackgroundDecoration: View {
    var body: some View {
        GeometryReader { proxy in
            Circle()
                .fill(AppColors.accent.opacity(0.08))
                .frame(width: proxy.size.width * 0.9)
                .blur(radius: 2)
                .offset(
                    x: proxy.size.width * 0.42,
                    y: -proxy.size.height * 0.12
                )

            Circle()
                .fill(AppColors.accent.opacity(0.05))
                .frame(width: proxy.size.width * 0.7)
                .offset(
                    x: -proxy.size.width * 0.35,
                    y: proxy.size.height * 0.72
                )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct WelcomeMarkView: View {
    @State private var isAnimated = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColors.accent.opacity(0.12))
                .frame(width: 204, height: 204)
                .scaleEffect(pulse ? 1.08 : 0.92)

            Circle()
                .stroke(AppColors.accent.opacity(0.2), lineWidth: 1)
                .frame(width: 170, height: 170)
                .scaleEffect(pulse ? 0.96 : 1.08)

            HStack(spacing: -20) {
                profileShape
                    .offset(x: isAnimated ? 9 : -34)
                    .rotationEffect(.degrees(isAnimated ? -7 : -18))

                profileShape
                    .scaleEffect(x: -1, y: 1)
                    .offset(x: isAnimated ? -9 : 34)
                    .rotationEffect(.degrees(isAnimated ? 7 : 18))
            }

            Image(systemName: "heart.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(AppColors.accent)
                .scaleEffect(isAnimated ? 1 : 0.1)
                .opacity(isAnimated ? 1 : 0)
        }
        .frame(height: 220)
        .onAppear {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.72)) {
                isAnimated = true
            }

            withAnimation(
                .easeInOut(duration: 1.8)
                .repeatForever(autoreverses: true)
            ) {
                pulse = true
            }
        }
        .accessibilityHidden(true)
    }

    private var profileShape: some View {
        VStack(spacing: 8) {
            Circle()
                .frame(width: 44, height: 44)

            Capsule()
                .frame(width: 64, height: 78)
        }
        .foregroundStyle(AppColors.foreground.opacity(0.84))
    }
}

#Preview {
    NavigationStack {
        WelcomeView(
            onGetStarted: {},
            onSignIn: {}
        )
    }
}
