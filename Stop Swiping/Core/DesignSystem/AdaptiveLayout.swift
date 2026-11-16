import SwiftUI

/// Sizing shared by every full-screen composition, so the app reads the same
/// on a small iPhone, iPhone Duo folded or open, and a 13-inch iPad.
///
/// Layouts follow the space they are given rather than the device, so they
/// change continuously while a window is resized, the iPad rotates or the
/// iPhone Duo unfolds, instead of jumping between fixed layouts.
enum AdaptiveLayout {
    /// The tallest band a screen with content on top and buttons at the
    /// bottom uses. Taller windows (iPad portrait) centre that band, so the
    /// buttons stay near the content instead of sinking to the far edge.
    /// Every iPhone, and iPhone Duo open, is shorter than this.
    static let stageMaxHeight: CGFloat = 960
    /// A comfortable line length for conversations and reading.
    static let readableWidth: CGFloat = 640

    /// Space above and below the centred band in a container this tall.
    static func stageInset(forHeight height: CGFloat) -> CGFloat {
        max(0, (height - stageMaxHeight) / 2)
    }
}

extension View {
    /// Limits a full-height screen to `AdaptiveLayout.stageMaxHeight` and
    /// centres it vertically. Apply it inside any background that should
    /// still reach the screen's edges.
    func adaptiveStageHeight() -> some View {
        frame(maxHeight: AdaptiveLayout.stageMaxHeight)
            .frame(maxHeight: .infinity)
    }

    /// Centres content in a column no wider than `width`.
    func readableColumn(_ width: CGFloat = AdaptiveLayout.readableWidth) -> some View {
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
    }
}
