import SwiftUI

/// An info button that opens a compact popover instead of a full sheet,
/// so the explanation never takes the user out of the step.
struct InfoPopoverButton: View {
    let title: String
    let message: String
    var isSuperscript = false

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: isSuperscript ? 11 : 17, weight: .medium))
                .foregroundStyle(OnboardingTheme.secondaryText)
                .offset(y: isSuperscript ? -7 : 0)
                .frame(width: isSuperscript ? 18 : 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n("More about \(title)"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(idealWidth: 320, maxWidth: 340, alignment: .leading)
            .presentationCompactAdaptation(.popover)
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .combine)
        }
    }
}
