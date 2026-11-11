import SwiftUI

enum SelectionStyle {
    case single
    case multiple
}

/// A selectable row. Selection is shown by the indicator's shape and a check
/// mark as well as by color, so it never relies on color alone.
struct SelectionOption: View {
    let title: String
    var detail: String?
    let isSelected: Bool
    let style: SelectionStyle
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.body, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(OnboardingTheme.primaryText.opacity(isSelected ? 1 : 0.86))
                    if let detail {
                        Text(detail)
                            .font(.system(.footnote))
                            .foregroundStyle(OnboardingTheme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

                SelectionIndicator(isSelected: isSelected, style: style)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 64)
            .background { background }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(SelectionPressStyle())
        .animation(OnboardingMotion.resolved(OnboardingMotion.selection, reduceMotion: reduceMotion), value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(style == .multiple ? "Multiple options can be selected." : "")
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return shape
            .fill(isSelected ? AnyShapeStyle(selectedFill) : AnyShapeStyle(OnboardingTheme.surface))
            .overlay {
                shape.strokeBorder(
                    isSelected ? AnyShapeStyle(OnboardingTheme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.09)),
                    lineWidth: isSelected ? 1.5 : 1
                )
            }
            .shadow(color: OnboardingTheme.blue.opacity(isSelected ? 0.35 : 0), radius: 18, y: 6)
    }

    private var selectedFill: LinearGradient {
        LinearGradient(
            colors: [OnboardingTheme.blue.opacity(0.22), OnboardingTheme.violet.opacity(0.16)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct SelectionIndicator: View {
    let isSelected: Bool
    let style: SelectionStyle

    var body: some View {
        ZStack {
            shape
                .strokeBorder(.white.opacity(isSelected ? 0 : 0.32), lineWidth: 1.5)
            shape
                .fill(OnboardingTheme.accentGradient)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(isSelected ? 1 : 0.6)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(isSelected ? 1 : 0.4)
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    private var shape: AnyInsettableShape {
        style == .single
            ? AnyInsettableShape(Circle())
            : AnyInsettableShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SelectionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(duration: 0.22, bounce: 0.3), value: configuration.isPressed)
    }
}

private struct AnyInsettableShape: InsettableShape {
    private let pathBuilder: @Sendable (CGRect) -> Path
    private let insetBuilder: @Sendable (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        pathBuilder = { shape.path(in: $0) }
        insetBuilder = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { insetBuilder(amount) }
}

/// A vertical list of options with single or multiple selection.
struct SelectionGroup<Item: Hashable>: View {
    let items: [Item]
    let style: SelectionStyle
    let title: (Item) -> String
    let isSelected: (Item) -> Bool
    let onSelect: (Item) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(items, id: \.self) { item in
                SelectionOption(
                    title: title(item),
                    isSelected: isSelected(item),
                    style: style,
                    action: { onSelect(item) }
                )
            }
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
    }
}
