import SwiftUI

struct PartnerHeightRangeStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingBound: HeightBound?

    private enum HeightBound: String, Identifiable {
        case minimum, maximum
        var id: String { rawValue }
        var title: String { self == .minimum ? L10n("Shortest height") : L10n("Tallest height") }
    }

    var body: some View {
        let range = viewModel.state.partnerHeightRange

        VStack(spacing: 26) {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    number(range.minimum, bound: .minimum)
                    Text("–")
                        .font(.system(size: 44, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(OnboardingTheme.tertiaryText)
                    number(range.maximum, bound: .maximum)
                }
                Text(range.isAny ? L10n("cm · any height") : "cm")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .contentTransition(.opacity)
            }
            .animation(OnboardingMotion.resolved(.snappy(duration: 0.25), reduceMotion: reduceMotion), value: range)
            .accessibilityElement(children: .contain)

            VStack(spacing: 6) {
                DualRangeSlider(
                    lower: Binding(
                        get: { viewModel.state.partnerHeightRange.minimum },
                        set: { viewModel.updatePartnerMinimumHeight($0) }
                    ),
                    upper: Binding(
                        get: { viewModel.state.partnerHeightRange.maximum },
                        set: { viewModel.updatePartnerMaximumHeight($0) }
                    ),
                    bounds: PartnerHeightRules.bounds,
                    lowerLabel: L10n("Shortest height"),
                    upperLabel: L10n("Tallest height"),
                    unit: "centimeters"
                )

                HStack {
                    Text(L10n("\(PartnerHeightRules.lowerBound) cm"))
                    Spacer()
                    Text(L10n("\(PartnerHeightRules.upperBound) cm"))
                }
                .font(.system(.footnote, design: .rounded).monospacedDigit())
                .foregroundStyle(OnboardingTheme.tertiaryText)
                .padding(.horizontal, 8)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 30)
        .onboardingSurface()
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .sheet(item: $editingBound) { bound in
            HeightInputSheet(
                title: bound.title,
                centimeters: bound == .minimum ? range.minimum : range.maximum
            ) { value in
                withAnimation(OnboardingMotion.resolved(.snappy(duration: 0.25), reduceMotion: reduceMotion)) {
                    if bound == .minimum {
                        viewModel.updatePartnerMinimumHeight(value)
                    } else {
                        viewModel.updatePartnerMaximumHeight(value)
                    }
                }
            }
        }
    }

    private func number(_ value: Int, bound: HeightBound) -> some View {
        Button {
            editingBound = bound
        } label: {
            Text("\(value)")
                .font(.system(size: 64, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(OnboardingTheme.primaryText)
                .contentTransition(.numericText(value: Double(value)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bound.title)
        .accessibilityValue(L10n("\(value) cm"))
        .accessibilityHint(L10n("Tap a number to edit"))
    }
}

private struct HeightInputSheet: View {
    let title: String
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    init(title: String, centimeters: Int, onSave: @escaping (Int) -> Void) {
        self.title = title
        self.onSave = onSave
        _input = State(initialValue: String(centimeters))
    }

    private var value: Int? { HeightRules.centimeters(from: input) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField(title, text: $input, selection: $selection)
                        .font(.system(size: 64, weight: .light, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .focused($isFocused)
                        .tint(OnboardingTheme.cyan)
                        .accessibilityIdentifier("partnerHeightInput")
                        .onSubmit(save)
                    Text("cm")
                        .font(.system(.title3, weight: .medium))
                        .foregroundStyle(OnboardingTheme.secondaryText)
                }
                .foregroundStyle(OnboardingTheme.primaryText)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(OnboardingTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(OnboardingTheme.accentGradient, lineWidth: 1)
                }

                Text(L10n("\(PartnerHeightRules.lowerBound)–\(PartnerHeightRules.upperBound) cm"))
                    .font(.system(.subheadline, design: .rounded).monospacedDigit())
                    .foregroundStyle(OnboardingTheme.secondaryText)

                Button(L10n("Save"), action: save)
                    .buttonStyle(GlowButtonStyle())
                    .disabled(value == nil)
                    .accessibilityIdentifier("savePartnerHeight")

                Button(L10n("Cancel")) { dismiss() }
                    .buttonStyle(QuietButtonStyle())
            }
            .padding(24)
            .padding(.top, 12)
            .frame(maxWidth: OnboardingTheme.controlWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(OnboardingTheme.background)
        .preferredColorScheme(.dark)
        .task {
            isFocused = true
            selection = TextSelection(range: input.startIndex..<input.endIndex)
        }
    }

    private func save() {
        guard let value else { return }
        onSave(value)
        dismiss()
    }
}
