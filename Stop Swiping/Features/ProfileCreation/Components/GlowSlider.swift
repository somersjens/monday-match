import SwiftUI

private enum SliderMetrics {
    static let thumb: CGFloat = 30
    static let track: CGFloat = 6
    static let height: CGFloat = 56
}

/// Maps integer values onto the track. An exponent above 1 gives small values
/// more room, which suits distances.
struct SliderScale {
    let bounds: ClosedRange<Int>
    var exponent: Double = 1

    private var span: Double { Double(max(1, bounds.upperBound - bounds.lowerBound)) }

    func fraction(for value: Int) -> Double {
        let linear = Double(min(max(value, bounds.lowerBound), bounds.upperBound) - bounds.lowerBound) / span
        return pow(linear, 1 / exponent)
    }

    func value(for fraction: Double) -> Int {
        let clamped = min(max(fraction, 0), 1)
        return bounds.lowerBound + Int((pow(clamped, exponent) * span).rounded())
    }
}

private struct SliderTrack: View {
    var body: some View {
        Capsule()
            .fill(.white.opacity(0.10))
            .frame(height: SliderMetrics.track)
            .padding(.horizontal, SliderMetrics.thumb / 2)
    }
}

private struct SliderFill: View {
    let isActive: Bool

    var body: some View {
        Capsule()
            .fill(OnboardingTheme.accentGradient)
            .frame(height: SliderMetrics.track)
            .shadow(color: OnboardingTheme.blue.opacity(isActive ? 0.9 : 0.55), radius: isActive ? 10 : 6)
    }
}

private struct SliderThumb: View {
    let isActive: Bool
    let isFocused: Bool

    var body: some View {
        Circle()
            .fill(.white)
            .overlay {
                Circle()
                    .strokeBorder(OnboardingTheme.accentGradient, lineWidth: 3)
                    .padding(-1)
            }
            .overlay {
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .padding(-7)
                    .opacity(isFocused ? 1 : 0)
            }
            .frame(width: SliderMetrics.thumb, height: SliderMetrics.thumb)
            .shadow(color: OnboardingTheme.cyan.opacity(isActive ? 0.75 : 0.35), radius: isActive ? 14 : 8)
            .scaleEffect(isActive ? 1.14 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.35), value: isActive)
    }
}

struct DualRangeSlider: View {
    enum Thumb: Hashable {
        case lower
        case upper
    }

    @Binding var lower: Int
    @Binding var upper: Int
    let bounds: ClosedRange<Int>
    var lowerLabel = L10n("Minimum")
    var upperLabel = L10n("Maximum")
    var unit = ""

    @State private var activeThumb: Thumb?
    @FocusState private var focusedThumb: Thumb?

    private var scale: SliderScale { SliderScale(bounds: bounds) }

    var body: some View {
        GeometryReader { geometry in
            let usable = max(1, geometry.size.width - SliderMetrics.thumb)
            let lowerX = scale.fraction(for: lower) * usable
            let upperX = scale.fraction(for: upper) * usable

            ZStack(alignment: .leading) {
                SliderTrack()
                SliderFill(isActive: activeThumb != nil)
                    .frame(width: max(SliderMetrics.track, upperX - lowerX))
                    .offset(x: lowerX + SliderMetrics.thumb / 2)
                thumb(.lower, at: lowerX)
                thumb(.upper, at: upperX)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(usable: usable, lowerX: lowerX, upperX: upperX))
        }
        .frame(height: SliderMetrics.height)
        .sensoryFeedback(.selection, trigger: lower)
        .sensoryFeedback(.selection, trigger: upper)
        .accessibilityElement(children: .contain)
    }

    private func thumb(_ which: Thumb, at x: CGFloat) -> some View {
        let value = which == .lower ? lower : upper
        return SliderThumb(isActive: activeThumb == which, isFocused: focusedThumb == which)
            .offset(x: x)
            .focusable()
            .focused($focusedThumb, equals: which)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { nudge(which, by: -1); return .handled }
            .onKeyPress(.rightArrow) { nudge(which, by: 1); return .handled }
            .accessibilityElement()
            .accessibilityLabel(which == .lower ? lowerLabel : upperLabel)
            .accessibilityValue(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
            .accessibilityAdjustableAction { direction in
                nudge(which, by: direction == .increment ? 1 : -1)
            }
    }

    private func dragGesture(usable: CGFloat, lowerX: CGFloat, upperX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if activeThumb == nil {
                    let start = drag.startLocation.x - SliderMetrics.thumb / 2
                    let toLower = abs(start - lowerX)
                    let toUpper = abs(start - upperX)
                    if abs(toLower - toUpper) < 0.5 {
                        // Stacked thumbs: the first movement decides which one moves.
                        guard abs(drag.translation.width) > 2 else { return }
                        activeThumb = drag.translation.width < 0 ? .lower : .upper
                    } else {
                        activeThumb = toLower < toUpper ? .lower : .upper
                    }
                }
                let position = drag.location.x - SliderMetrics.thumb / 2
                if let activeThumb {
                    set(activeThumb, to: scale.value(for: position / usable))
                }
            }
            .onEnded { _ in activeThumb = nil }
    }

    private func nudge(_ which: Thumb, by delta: Int) {
        set(which, to: (which == .lower ? lower : upper) + delta)
    }

    /// Thumbs can meet but never cross.
    private func set(_ which: Thumb, to value: Int) {
        switch which {
        case .lower:
            let next = min(max(value, bounds.lowerBound), upper)
            if next != lower { lower = next }
        case .upper:
            let next = max(min(value, bounds.upperBound), lower)
            if next != upper { upper = next }
        }
    }
}

struct GlowSlider: View {
    @Binding var value: Int
    let scale: SliderScale
    let label: String
    let valueDescription: (Int) -> String

    @State private var isDragging = false
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let usable = max(1, geometry.size.width - SliderMetrics.thumb)
            let x = scale.fraction(for: value) * usable

            ZStack(alignment: .leading) {
                SliderTrack()
                SliderFill(isActive: isDragging)
                    .frame(width: max(SliderMetrics.track, x))
                    .offset(x: SliderMetrics.thumb / 2)
                SliderThumb(isActive: isDragging, isFocused: isFocused)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        update(scale.value(for: (drag.location.x - SliderMetrics.thumb / 2) / usable))
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: SliderMetrics.height)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { update(value - 1); return .handled }
        .onKeyPress(.rightArrow) { update(value + 1); return .handled }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueDescription(value))
        .accessibilityAdjustableAction { direction in
            let step = max(1, value / 10)
            update(value + (direction == .increment ? step : -step))
        }
    }

    private func update(_ newValue: Int) {
        let clamped = min(max(newValue, scale.bounds.lowerBound), scale.bounds.upperBound)
        if clamped != value { value = clamped }
    }
}
