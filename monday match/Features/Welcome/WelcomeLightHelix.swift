import CoreGraphics
import Foundation

/// A double helix rewoven from the heart's filaments, standing upright and
/// spinning about its own axis. The outer sheets of both rings run up one
/// backbone and down the other as a single closed loop, meeting at the
/// tapered ends. Each backbone is a broad, translucent band of silk standing
/// out from the cylinder, so it reads widest at the sides; the blue sheets
/// hang between them as fine twisted base pairs. Coordinates match
/// `WelcomeLightGeometry`'s normalized space, and the Metal shader mirrors
/// this function exactly.
enum WelcomeLightHelix {
    static let radius = 0.31
    static let halfHeight = 1.02
    /// Radians of turn per unit of height.
    static let twist = 5.5
    /// Radians per second about the helix's own axis.
    static let spin = 0.6
    /// Base pairs drawn by each ring on each pass along the helix.
    static let rungsPerPass = 10.0

    /// Position along the axis from -1 to 1, travelling the full length and
    /// back once per loop with an even pace between the ends.
    static func height(phase: Double) -> Double {
        asin(0.995 * cos(phase)) / asin(0.995)
    }

    /// Narrows the helix only near its ends, where both backbones meet.
    static func envelope(height: Double) -> Double {
        sqrt(max(0, 1 - pow(abs(height), 4)))
    }

    static func point(u: Double, ring: Int, strand: Int, seconds: Double) -> (point: CGPoint, depth: Double) {
        let sheet = strand / 20
        let laneIndex = strand % 20
        let lane = Double(laneIndex) / 19 * 2 - 1
        let ringValue = Double(ring)
        let sheetValue = Double(sheet)
        let phase = (u + 0.5) * WelcomeLightGeometry.tau
        let h = height(phase: phase)
        let envelope = envelope(height: h)
        let axial = h * halfHeight
        let turn = twist * axial + spin * seconds
        // A slow swell travels up the helix, so it breathes like the heart.
        let swell = 1 + 0.03 * sin(2.2 * axial - 0.9 * seconds)
        let seed = Double(strand) * 1.37 + ringValue * 4.1
        var y = axial
        var r: Double
        var theta: Double
        if sheet == 1 {
            // Sweeps across the axis between the backbones, once per base pair.
            // Both passes over a pair are thin threads waving in opposite
            // directions, so together they read as a twisted double line.
            let offset = ring == 0 ? 0 : Double.pi / 2
            let angle = rungsPerPass * phase + offset
            // An even crossing speed gives every pair enough samples to wave
            // smoothly; the turns near the backbones are hidden by the shader.
            let sweep = sin(angle)
            let middle = 1 - sweep * sweep
            // Each pair lies level at the height where it crosses the axis;
            // between pairs the thread follows the backbone, hidden in it.
            let center = ((angle / Double.pi).rounded() * Double.pi - offset) / rungsPerPass
            let level = axial + (height(phase: center) * halfHeight - axial) * smoothstep(0, 0.3, middle)
            let pass = 1.4 * tanh(sin(phase) / 0.05)
            r = (radius - 0.02) * swell * sweep * envelope
            theta = twist * level + spin * seconds + lane * 0.04 * middle
            y = level + lane * (0.0015 + 0.006 * middle * cos(4 * sweep + 0.9 * seconds + ringValue + pass)) * envelope
                + 0.02 * middle * sin(3.6 * sweep + 1.2 * seconds + pass * 1.1 + ringValue) * envelope
                + 0.006 * middle * sin(1.3 * seconds + 5 * level + ringValue * 2.1)
        } else {
            // Half a turn apart on the way up and on the way down. The swap
            // happens right at the tips, where the envelope has closed.
            let side = ring == 0 ? 1.0 : -1.0
            let across = Double.pi / 2 * tanh(sin(phase) / 0.03) * side
            theta = turn + Double.pi / 2 + across
            // Both rings share each backbone as two layers of the band that
            // roll slowly past each other.
            let ply = 2.2 * axial + 0.5 * seconds
            let plyOffset = 0.022 * side
            // The band mostly faces outward and only turns a little, with its
            // width breathing along its length. The blue sheet lies on the
            // outside of it, the violet one on the inside.
            let torsion = 0.45 * sin(1.6 * axial + 0.5 * seconds + ringValue * 1.9 + sheetValue * 1.3)
            let width = 0.06 + 0.02 * sin(3.1 * axial - 1.1 * seconds + ringValue + sheetValue * 0.7)
            let separation = (1 - sheetValue) * 0.026 * (1 + 0.5 * sin(1.7 * axial + 0.6 * seconds + ringValue))
            let braid = 0.008 * sin(9 * axial + lane * 2.4 - 1.7 * seconds + sheetValue * 2 + ringValue * 3)
                + 0.003 * sin(seed + 0.8 * seconds)
            let offset = lane * width + separation + braid
            // Near the ends the band loosens, so the tips taper softly.
            let taper = 0.35 + 0.65 * envelope
            r = radius * swell * envelope + (offset * cos(torsion) + plyOffset * cos(ply)) * taper
            y += (offset * sin(torsion) + plyOffset * sin(ply)) * taper
            theta += lane * 0.05 * taper
            // The outermost thread of each sheet drifts free as a faint aura.
            if laneIndex == 19 {
                r += (0.04 + 0.025 * sin(2.3 * axial + 0.7 * seconds + ringValue * 2)) * envelope
            }
        }
        let x = r * sin(theta), z = r * cos(theta)
        let perspective = 1 / (1 - z * 0.30)
        return (CGPoint(x: x * perspective, y: y * perspective), (radius - z) * 0.8)
    }

    private static func smoothstep(_ from: Double, _ to: Double, _ value: Double) -> Double {
        let t = min(max((value - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
