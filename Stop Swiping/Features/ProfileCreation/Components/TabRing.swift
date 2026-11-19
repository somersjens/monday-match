import SwiftUI

/// The outline around the active tab, travelling from 0 (own) to 1
/// (partner). Its edges follow the progress at different moments, so the
/// front edge sets off first, the ring stretches over both tabs glowing,
/// and the back edge catches up; a spring's overshoot squeezes it as it
/// lands. Going back, the other edge leads.
struct TabRing: View, Animatable {
    var progress: CGFloat
    let spacing: CGFloat
    let fill: LinearGradient

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// How far behind the trailing edge the leading edge runs.
    private static let lag: CGFloat = 0.35

    var body: some View {
        GeometryReader { proxy in
            let tabWidth = max(0, (proxy.size.width - spacing) / 2)
            let travel = tabWidth + spacing
            let trailing = min(1, progress / (1 - Self.lag))
            let leading = max(0, (progress - Self.lag) / (1 - Self.lag))
            let minX = leading * travel
            let maxX = max(minX + tabWidth * 0.82, tabWidth + trailing * travel)
            // 0 when resting on a tab, up to 1 when spanning both.
            let stretch = travel > 0 ? min(1, max(0, (maxX - minX - tabWidth) / travel)) : 0
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

            shape
                .fill(fill)
                .overlay {
                    shape.strokeBorder(OnboardingTheme.accentGradient, lineWidth: 1.2 + 0.9 * stretch)
                }
                .shadow(color: OnboardingTheme.cyan.opacity(0.6 * stretch), radius: 3 + 12 * stretch)
                .frame(width: maxX - minX, height: proxy.size.height)
                .offset(x: minX)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
