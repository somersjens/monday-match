import Foundation

nonisolated enum FaceCameraRotation {
    /// Use the camera-specific coordinator angle. Snap to a quadrant so small
    /// hand movements don't reconfigure capture and reset the scan repeatedly.
    static func quarterTurn(for degrees: CGFloat) -> CGFloat? {
        guard degrees.isFinite else { return nil }
        let angle = ((degrees / 90).rounded() * 90).truncatingRemainder(dividingBy: 360)
        return angle < 0 ? angle + 360 : angle
    }
}
