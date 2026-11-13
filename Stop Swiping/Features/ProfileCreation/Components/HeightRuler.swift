import SwiftUI

/// A horizontally scrolling centimetre ruler that snaps to whole values.
///
/// The value is derived from the content offset: with half a viewport of
/// padding on each side, an offset of `n × tickSpacing` centres the n-th tick.
struct HeightRuler: View {
    @Binding var centimeters: Int
    let range: ClosedRange<Int>

    @State private var position = ScrollPosition()
    /// The last value the ruler reported, so it does not scroll itself back.
    @State private var reportedValue: Int?
    /// Set while scrolling programmatically; ticks passed on the way are not
    /// selections.
    @State private var pendingValue: Int?
    @State private var offsetValue: Int?
    @State private var viewportWidth: CGFloat = 0
    @FocusState private var isFocused: Bool

    private let tickSpacing: CGFloat = 10
    private let height: CGFloat = 96

    init(centimeters: Binding<Int>, range: ClosedRange<Int>) {
        _centimeters = centimeters
        self.range = range
        _pendingValue = State(initialValue: centimeters.wrappedValue)
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                Color.clear.frame(width: padding)
                ForEach(Array(range), id: \.self) { value in
                    RulerTick(value: value)
                        .frame(width: tickSpacing, height: height, alignment: .top)
                        .onTapGesture { centimeters = value }
                }
                Color.clear.frame(width: padding)
            }
        }
        .scrollPosition($position)
        .scrollTargetBehavior(TickSnapping(spacing: tickSpacing))
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            viewportWidth = width
            scroll(to: centimeters, animated: false)
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x + $0.contentInsets.leading }) { _, offset in
            let value = value(forOffset: offset)
            offsetValue = value
            if let pending = pendingValue {
                if pending == value { pendingValue = nil }
                return
            }
            guard value != centimeters else { return }
            reportedValue = value
            centimeters = value
        }
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { pendingValue = nil }
        }
        .frame(height: height)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.22),
                    .init(color: .black, location: 0.78),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .overlay(alignment: .top) { indicator }
        .onChange(of: centimeters) { _, value in
            guard value != reportedValue else { return }
            scroll(to: value, animated: true)
        }
        .sensoryFeedback(.selection, trigger: centimeters)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { nudge(-1); return .handled }
        .onKeyPress(.rightArrow) { nudge(1); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n("Height"))
        .accessibilityValue(L10n("\(centimeters) centimeters"))
        .accessibilityAdjustableAction { direction in
            nudge(direction == .increment ? 1 : -1)
        }
    }

    private var indicator: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(LinearGradient(colors: [OnboardingTheme.cyan, OnboardingTheme.violet], startPoint: .top, endPoint: .bottom))
                .frame(width: 3, height: 52)
                .shadow(color: OnboardingTheme.cyan.opacity(0.8), radius: 8)
            Circle()
                .fill(OnboardingTheme.violet)
                .frame(width: 6, height: 6)
                .shadow(color: OnboardingTheme.violet, radius: 6)
                .offset(y: -2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(isFocused ? 0.7 : 0), lineWidth: 2)
                .frame(width: 22, height: 70)
        }
        .allowsHitTesting(false)
    }

    private var padding: CGFloat {
        max(0, (viewportWidth - tickSpacing) / 2)
    }

    private func value(forOffset offset: CGFloat) -> Int {
        let steps = Int((offset / tickSpacing).rounded())
        return min(max(range.lowerBound + steps, range.lowerBound), range.upperBound)
    }

    private func scroll(to value: Int, animated: Bool) {
        guard viewportWidth > 0 else { return }
        reportedValue = value
        pendingValue = value == offsetValue ? nil : value
        withAnimation(animated ? .snappy(duration: 0.3) : nil) {
            position.scrollTo(x: CGFloat(value - range.lowerBound) * tickSpacing)
        }
    }

    private func nudge(_ delta: Int) {
        let next = min(max(centimeters + delta, range.lowerBound), range.upperBound)
        if next != centimeters { centimeters = next }
    }
}

/// Flings come to rest exactly on a centimetre.
private struct TickSnapping: ScrollTargetBehavior {
    let spacing: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin.x = (target.rect.minX / spacing).rounded() * spacing
    }
}

private struct RulerTick: View {
    let value: Int

    var body: some View {
        let isMajor = value % 10 == 0
        let isMid = value % 5 == 0
        ZStack(alignment: .top) {
            Capsule()
                .fill(.white.opacity(isMajor ? 0.8 : (isMid ? 0.45 : 0.22)))
                .frame(width: isMajor ? 2 : 1.5, height: isMajor ? 38 : (isMid ? 26 : 16))
                .padding(.top, 4)
            if isMajor {
                Text(String(value))
                    .font(.system(.caption, design: .rounded, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize()
                    .padding(.top, 54)
            }
        }
    }
}
