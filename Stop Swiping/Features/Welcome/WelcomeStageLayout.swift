import CoreGraphics

/// Where the home screen's light sits and how large it is drawn, for a given
/// safe-area size. Every overlay that lines up with the light (match, chat
/// rings, personality labels, the exchange explanation) reads it from here.
///
/// The light follows both dimensions: a short screen (iPhone SE, iPhone Duo
/// folded) draws it smaller instead of letting it run into the controls, and
/// a tall one (iPad portrait) keeps it and the controls together in a centred
/// band. On every regular iPhone the result is the original layout.
struct WelcomeStageLayout: Equatable {
    /// Height kept free below the light for the home controls.
    static let controlsReserve: CGFloat = 160
    static let maximumWidth: CGFloat = 620
    /// The light's width as a share of the band it sits in. Tuned so iPhone
    /// 17 Pro and Pro Max keep their full-width light.
    static let heightRatio: CGFloat = 0.68

    let size: CGSize
    /// Space above the centred band; zero on every iPhone.
    let stageTop: CGFloat
    /// The band above the controls the light is centred in.
    let animationHeight: CGFloat
    /// Width of the light's drawable, which sets its scale.
    let animationWidth: CGFloat

    init(size: CGSize) {
        self.size = size
        stageTop = AdaptiveLayout.stageInset(forHeight: size.height)
        animationHeight = max(0, size.height - 2 * stageTop - Self.controlsReserve)
        // On short screens the controls (and the match labels, which hang
        // below the heart) are taller than the reserve, so the light also
        // keeps its lower half clear of them.
        let clearOfControls = (animationHeight / 2 - Self.lowerClearance) / Self.lowerExtent
        animationWidth = max(0, min(size.width, Self.maximumWidth, animationHeight * Self.heightRatio,
                                    clearOfControls))
    }

    /// How far the helix and the match scores reach below the light's centre,
    /// as a share of `animationWidth`.
    private static let lowerExtent: CGFloat = 0.43
    /// Extra room those need below the reserve, in points.
    private static let lowerClearance: CGFloat = 104

    /// The light's normalized unit in points.
    var unit: CGFloat { animationWidth * 0.42 }
    var lightCenter: CGPoint { CGPoint(x: size.width / 2, y: stageTop + animationHeight / 2) }
    var lightHeight: CGFloat { min(animationWidth * 1.12, animationHeight * 0.94) }
    /// The drawable extends past the incoming tail while keeping the light's
    /// scale, centre and stage transitions in the same place.
    var drawingHeight: CGFloat { max(animationWidth * 2.1, lightHeight) }
}
