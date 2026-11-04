import SwiftUI

struct WelcomeView: View {
    let onGetStarted: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let animationHeight = max(0, proxy.size.height - 160)
            let animationWidth = min(proxy.size.width, 620)

            ZStack {
                Color(red: 0.008, green: 0.012, blue: 0.035)
                    .ignoresSafeArea()

                WelcomeLightAnimation()
                    .frame(
                        width: animationWidth,
                        // Keep the heart's scale/center, but let its incoming
                        // tail reach the screen edge beyond the heart's bounds.
                        height: max(animationWidth * 2.1, min(proxy.size.width * 1.12, animationHeight * 0.94))
                    )
                    .position(x: proxy.size.width / 2, y: animationHeight / 2)

                VStack {
                    Spacer(minLength: 0)

                    VStack(spacing: 12) {
                        Button(action: onGetStarted) {
                            Text("Get started")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 58)
                                .background {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.22, green: 0.42, blue: 0.94),
                                                    Color(red: 0.40, green: 0.29, blue: 0.86)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)

                        Button("I already have an account", action: onSignIn)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 18)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack {
        WelcomeView(onGetStarted: {}, onSignIn: {})
    }
}
