import SwiftUI

extension View {
    /// Keeps a sheet's content at the width it was first laid out for.
    /// Half-height sheets float with a margin on each side and full-height
    /// ones reach the edges, so a sheet widens while it is pulled up; without
    /// this, bars, rows and line breaks stretch along the way.
    func keepsSheetWidth() -> some View {
        modifier(SheetWidthKeeper())
    }
}

struct SheetWidthKeeper: ViewModifier {
    @State private var width: CGFloat?

    func body(content: Content) -> some View {
        content
            .frame(width: width)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { sheetWidth in
                width = Self.contentWidth(keeping: width, sheetWidth: sheetWidth)
            }
    }

    /// Keeps the width the content was laid out for while the sheet only
    /// grows a little (its side margins going away as it moves to full
    /// height). A narrower sheet always wins, so nothing is cut off; a much
    /// wider one (rotating, resizing the window) gets the room.
    static func contentWidth(keeping current: CGFloat?, sheetWidth width: CGFloat) -> CGFloat {
        guard let current, width >= current, width - current < 48 else { return width }
        return current
    }
}
