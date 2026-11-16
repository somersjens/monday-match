import SwiftUI

extension VerticalAlignment {
    private enum HeaderTitle: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }

    /// Lines a screen title up with the round button beside it. Views without
    /// an explicit guide (the buttons) use their vertical centre.
    static let headerTitle = VerticalAlignment(HeaderTitle.self)
}

extension View {
    /// Puts the `.headerTitle` guide on the optical centre of a one-line
    /// title (halfway up its capitals), so it stays centred on the button
    /// next to it even when `minimumScaleFactor` shrinks the text.
    func headerTitleGuide() -> some View {
        alignmentGuide(.headerTitle) { d in
            // Capitals are ~0.7 of the font size; the line box is ~1.2 of it.
            d[.firstTextBaseline] - d.height * 0.29
        }
    }
}
