import SwiftUI

extension View {
    /// Asks once, in the app's own night style, before something that can't
    /// be undone. `action` runs after the sheet has gone, so it may remove
    /// the screen that showed it.
    func destructiveConfirmation(
        isPresented: Binding<Bool>,
        confirmTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        modifier(DestructiveConfirmationModifier(isPresented: isPresented,
                                                 confirmTitle: confirmTitle,
                                                 action: action))
    }
}

private struct DestructiveConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let confirmTitle: String
    let action: () -> Void

    @State private var confirmed = false

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            guard confirmed else { return }
            confirmed = false
            action()
        }) {
            ConfirmationSheet(confirmTitle: confirmTitle) {
                confirmed = true
                isPresented = false
            }
        }
    }
}

/// Only what matters: it can't be undone, do it, or don't.
private struct ConfirmationSheet: View {
    let confirmTitle: String
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 220

    var body: some View {
        VStack(spacing: 20) {
            Text(L10n("This can’t be undone"))
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(OnboardingTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(DestructiveGlowButtonStyle())
                    .accessibilityIdentifier("confirmation.confirm")
                Button(L10n("Cancel")) { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("confirmation.cancel")
            }
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(OnboardingTheme.background)
        .preferredColorScheme(.dark)
    }
}

/// `GlowButtonStyle` for an action that can't be undone.
struct DestructiveGlowButtonStyle: ButtonStyle {
    static let gradient = LinearGradient(
        colors: [Color(red: 0.93, green: 0.25, blue: 0.36), Color(red: 0.86, green: 0.27, blue: 0.62)],
        startPoint: .leading,
        endPoint: .trailing
    )

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: OnboardingTheme.buttonHeight)
            .background {
                RoundedRectangle(cornerRadius: 20).fill(Self.gradient)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.16), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            ConfirmationSheet(confirmTitle: "Delete match") {}
        }
}
