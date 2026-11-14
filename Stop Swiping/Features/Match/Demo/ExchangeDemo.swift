import SwiftUI

/// The explanation played once the profile is finished. This screen shrinks
/// into a phone beside a second one, both turn until their tops meet, each
/// helix leaves for the other phone, and this phone turns back and grows
/// into the real screen while the match forms on it.
enum ExchangeDemo {
    enum Phase: Int, Comparable {
        /// Two phones side by side, each with its helix.
        case apart
        /// Turned a quarter, top to top.
        case together
        /// The helices cross over and the match starts coming back.
        case exchange
        /// This phone turns back and becomes the screen again.
        case takeover

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static let shrink = Animation.spring(duration: 0.9, bounce: 0.12)
    static let turn = Animation.smooth(duration: 1.25)
    static let takeover = Animation.spring(duration: 1.15, bounce: 0.06)

    /// How long the phones stand side by side, shrinking included.
    static let apartDuration = 3.0
    /// The turn, and a short rest once the tops touch.
    static let togetherDuration = 1.6
    /// From the start of the exchange until this phone turns back: the
    /// helix has left and the first threads of the match have come in.
    static let takeoverDelay = WelcomeLightMatch.exitDuration + 0.8
    static let takeoverDuration = 1.15
}

/// Where a phone is in the demo. Every value animates.
struct ExchangeDemoPose: Equatable {
    /// 0 is the real screen; 1 a phone on the demo's stage.
    var shrink = 0.0
    /// 0 upright; 1 a quarter turn, top towards the other phone.
    var turn = 0.0
    /// 1 waits past the edge of the screen.
    var away = 0.0

    static let screen = ExchangeDemoPose()
    static let apart = ExchangeDemoPose(shrink: 1)
    static let together = ExchangeDemoPose(shrink: 1, turn: 1)
    static let gone = ExchangeDemoPose(shrink: 1, turn: 1, away: 1)
}

/// Lays both phones out on the whole screen, safe areas included.
struct ExchangeDemoStage {
    let screen: CGSize
    /// Whether the device has a sensor housing at the top of its screen.
    let hasHousing: Bool
    /// The device's own corners, near enough.
    var cornerRadius: CGFloat { hasHousing ? 55 : 24 }

    /// How far below the top of the glass the helix ends, tapered tip aside.
    let helixReach: CGFloat

    /// - Parameters:
    ///   - helixCenter: The helix's centre, measured down from the top of `size`.
    ///   - helixUnit: Points per unit of the light's normalized space.
    init(size: CGSize, insets: EdgeInsets, helixCenter: CGFloat, helixUnit: CGFloat) {
        screen = CGSize(width: size.width + insets.leading + insets.trailing,
                        height: size.height + insets.top + insets.bottom)
        hasHousing = insets.top >= 44
        helixReach = insets.top + helixCenter + helixUnit * WelcomeLightHelix.halfHeight * 0.85
    }

    /// Two phones fit side by side, with room for the caption above them.
    private var uprightScale: CGFloat {
        max(0.2, min(0.42, (screen.width - 44) / (2 * screen.width), (screen.height - 320) / screen.height))
    }

    /// Lying top to top, half of each phone may leave the screen, but its
    /// helix stays in view.
    private var lyingScale: CGFloat {
        min(uprightScale, screen.width / 2 / max(helixReach, 1))
    }

    func scale(turn: Double) -> CGFloat {
        uprightScale + (lyingScale - uprightScale) * CGFloat(turn)
    }

    func centerY(turn: Double) -> CGFloat {
        screen.height * (0.52 - 0.07 * turn)
    }

    /// The gap between the tops once they touch.
    var seam: CGRect {
        let thickness = screen.width * lyingScale
        return CGRect(x: screen.width / 2 - 2, y: centerY(turn: 1) - thickness / 2, width: 4, height: thickness)
    }

    struct Placement {
        let scale: CGFloat
        let angle: Angle
        let center: CGPoint
    }

    /// The phones hinge on the top corners they share, so they open into a
    /// Λ and lie down top to top without ever passing through each other.
    /// - Parameter side: -1 for the phone on the left, 1 for the one on the right.
    func placement(side: CGFloat, pose: ExchangeDemoPose) -> Placement {
        let turn = CGFloat(pose.turn), shrink = CGFloat(pose.shrink)
        let scale = scale(turn: pose.turn)
        let width = screen.width * scale, height = screen.height * scale
        let angle = -side * .pi / 2 * turn
        let gap = 14 - 10 * turn
        let middle = centerY(turn: pose.turn)
        let pivot = CGPoint(x: screen.width / 2 + side * gap / 2,
                            y: (middle - height / 2) * (1 - turn) + (middle + width / 2) * turn)
        // The top corner next to the other phone, from the phone's centre.
        let corner = CGPoint(x: -side * width / 2, y: -height / 2)
        let staged = CGPoint(
            x: pivot.x - (corner.x * cos(angle) - corner.y * sin(angle)) + side * CGFloat(pose.away) * screen.width * 0.9,
            y: pivot.y - (corner.x * sin(angle) + corner.y * cos(angle)))
        return Placement(
            scale: 1 + (scale - 1) * shrink,
            angle: .radians(angle),
            center: CGPoint(x: screen.width / 2 + (staged.x - screen.width / 2) * shrink,
                            y: screen.height / 2 + (staged.y - screen.height / 2) * shrink))
    }
}

/// Turns its content into one of the demo's phones: the content is the
/// phone's screen, drawn at full size and placed on the stage. At rest it
/// leaves the content exactly where it is.
struct ExchangeDemoPhone: ViewModifier, Animatable {
    var pose: ExchangeDemoPose
    /// -1 for the phone on the left, 1 for the one on the right.
    let side: CGFloat
    let stage: ExchangeDemoStage
    /// The safe area between the content and the glass.
    let insets: EdgeInsets
    /// Covers light that the content draws above the top of its screen.
    var hidesOverflow = false

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(pose.shrink, AnimatablePair(pose.turn, pose.away)) }
        set { pose = ExchangeDemoPose(shrink: newValue.first, turn: newValue.second.first, away: newValue.second.second) }
    }

    func body(content: Content) -> some View {
        let placement = stage.placement(side: side, pose: pose)
        let size = CGSize(width: stage.screen.width - insets.leading - insets.trailing,
                          height: stage.screen.height - insets.top - insets.bottom)
        // The middle of the glass, in the content's own coordinates.
        let anchor = UnitPoint(
            x: (size.width / 2 + (insets.trailing - insets.leading) / 2) / max(size.width, 1),
            y: (size.height / 2 + (insets.bottom - insets.top) / 2) / max(size.height, 1))
        content
            .overlay {
                ExchangeDemoGlass(cornerRadius: stage.cornerRadius, scale: placement.scale,
                                  visibility: min(max(pose.shrink / 0.3, 0), 1),
                                  showsHousing: stage.hasHousing,
                                  hidesOverflow: hidesOverflow)
                    .padding(EdgeInsets(top: -insets.top, leading: -insets.leading,
                                        bottom: -insets.bottom, trailing: -insets.trailing))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .scaleEffect(placement.scale, anchor: anchor)
            .rotationEffect(placement.angle, anchor: anchor)
            .offset(x: placement.center.x - stage.screen.width / 2,
                    y: placement.center.y - stage.screen.height / 2)
    }
}

/// The edge of a phone: a hairline of the light's own colours with a soft
/// glow, the same weight on screen however small the phone is drawn.
private struct ExchangeDemoGlass: View {
    let cornerRadius: CGFloat
    /// How large the phone is drawn, so the line keeps its weight.
    let scale: CGFloat
    /// Fades the edge out as the phone becomes the screen.
    let visibility: Double
    let showsHousing: Bool
    let hidesOverflow: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let line = 1.5 / max(scale, 0.1)
        let edge = LinearGradient(
            colors: [OnboardingTheme.cyan, OnboardingTheme.blue, OnboardingTheme.violet, OnboardingTheme.pink.opacity(0.8)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack(alignment: .top) {
            shape.stroke(edge, lineWidth: line * 4)
                .blur(radius: line * 5)
                .opacity(0.55)
            shape.stroke(edge, lineWidth: line)
                .opacity(0.9)
            if showsHousing {
                Capsule()
                    .fill(.white.opacity(0.10))
                    .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: line * 0.5) }
                    .frame(width: 122, height: 36)
                    .padding(.top, 12)
            }
        }
        .opacity(visibility)
        .background(alignment: .top) {
            if hidesOverflow {
                // The light is drawn taller than the screen, for the threads
                // that arrive from above. On a phone they stop at its edge.
                Color("WelcomeBackground")
                    .frame(height: 900)
                    .offset(y: -900)
            }
        }
    }
}

/// The other person's phone: the same light, on a screen of its own.
struct ExchangeDemoPeerPhone: View {
    let stage: ExchangeDemoStage
    let lightSize: CGSize
    /// The light's centre, measured from the top-left of the glass.
    let lightCenter: CGPoint
    let match: WelcomeLightMatch.Request?
    let pose: ExchangeDemoPose

    var body: some View {
        WelcomeLightAnimation(form: .helix, skipsEntrance: true, match: match)
            .frame(width: lightSize.width, height: lightSize.height)
            .position(lightCenter)
            .frame(width: stage.screen.width, height: stage.screen.height)
            .background(Color("WelcomeBackground"))
            .clipShape(RoundedRectangle(cornerRadius: stage.cornerRadius, style: .continuous))
            .modifier(ExchangeDemoPhone(pose: pose, side: 1, stage: stage, insets: EdgeInsets()))
            .opacity(1 - pose.away)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Light gathers where the tops touch, and flares while the helices cross.
struct ExchangeDemoSeam: View {
    let phase: ExchangeDemo.Phase
    let height: CGFloat

    private var strength: Double {
        switch phase {
        case .apart, .takeover: 0
        case .together: 0.45
        case .exchange: 1
        }
    }

    var body: some View {
        let light = LinearGradient(
            colors: [.clear, OnboardingTheme.cyan, .white, OnboardingTheme.violet, .clear],
            startPoint: .top, endPoint: .bottom)
        ZStack {
            Capsule().fill(light)
                .frame(width: 34, height: height * 1.15)
                .blur(radius: 22)
                .opacity(0.5)
            Capsule().fill(light)
                .frame(width: 3, height: height * 0.92)
                .blur(radius: 2.5)
        }
        .blendMode(.plusLighter)
        .opacity(strength)
        .animation(phase == .together ? .easeOut(duration: 0.5).delay(1.0)
                   : .easeInOut(duration: phase == .takeover ? 0.25 : 0.6), value: phase)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What both people do, said above the phones.
struct ExchangeDemoCaption: View {
    let phase: ExchangeDemo.Phase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: Int? {
        switch phase {
        case .apart: 0
        case .together, .exchange: 1
        case .takeover: nil
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let step {
                VStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [OnboardingTheme.cyan, OnboardingTheme.violet],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .frame(width: 40, height: 40)
                        .background { Circle().fill(.white.opacity(0.08)) }
                        .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                        .accessibilityHidden(true)
                    Text(step == 0 ? L10n("Both turn on AirDrop") : L10n("Hold your phones together"))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                        .shadow(color: OnboardingTheme.blue.opacity(0.7), radius: 14)
                    if step == 1 {
                        Text(L10n("Top to top, and your profiles are exchanged."))
                            .font(.subheadline)
                            .foregroundStyle(OnboardingTheme.secondaryText)
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .id(step)
                .transition(.onboardingReveal(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 28)
        .animation(.easeInOut(duration: 0.45), value: step)
    }
}
