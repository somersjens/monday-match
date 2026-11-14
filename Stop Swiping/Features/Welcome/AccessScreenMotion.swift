import SwiftUI

/// Shared geometry keeps the live welcome renderer and its invisible return
/// target aligned. The renderer itself stays mounted throughout the transition.
enum AccessScreenMotion {
    static let headerHeight: CGFloat = 112
    static let lightCenterY: CGFloat = 52

    static func lightScale(for width: CGFloat) -> CGFloat {
        min(0.25, 94 / max(width, 1))
    }

    static func travel(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.95, bounce: 0.08)
    }
}

private struct AccessArrival: ViewModifier {
    let visible: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 24)
            .scaleEffect(visible || reduceMotion ? 1 : 0.975, anchor: .top)
            .blur(radius: visible || reduceMotion ? 0 : 9)
            .animation(reduceMotion ? .easeOut(duration: 0.18)
                       : .spring(duration: 0.75, bounce: 0.10).delay(delay), value: visible)
    }
}

extension View {
    func accessArrival(visible: Bool, delay: Double) -> some View {
        modifier(AccessArrival(visible: visible, delay: delay))
    }
}
