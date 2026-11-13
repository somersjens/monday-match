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

    /// Arc length along an inlet per unit of helix height, so a strand keeps
    /// roughly its pace as it passes from the inlet into the helix.
    static let inletPace = 1.6

    /// The two backbones are pulled in as loose strands. Each one sweeps up
    /// from a lower corner of the screen along a curved inlet, enters at the
    /// bottom tip and winds up its own helical path, so the pair braids
    /// together rather than arriving already twisted. Once they are in
    /// place, the base pairs are laid between them from the middle outwards.
    struct Arrival {
        static let delay = 0.05
        /// Time for the strands to be pulled all the way in.
        static let flight = 1.9
        /// Base pairs start just before the strands come to rest.
        static let rungsStart = 1.5
        static let rungsDuration = 0.8
        /// Everything has settled this long after `delay`.
        static let duration = rungsStart + rungsDuration
        static let settled = Arrival(travel: 0, reach: 0, rungs: 1, turn: 0, side: 1)

        /// How much helix height each backbone still has to be pulled
        /// through; zero once it rests in place.
        var travel: Double
        /// Horizontal distance from the bottom tip to the far end of each inlet.
        var reach: Double
        /// How far the base pairs have been laid, 0 to 1.
        var rungs: Double
        /// Extra turn about the axis that keeps both backbones leaving the
        /// bottom tip sideways while the strands come in, released to zero
        /// as they settle.
        var turn: Double
        /// 1 or -1: which backbone takes the right-hand inlet, chosen so each
        /// strand crosses the tip and carries on into the opposite arc.
        var side: Double

        private init(travel: Double, reach: Double, rungs: Double, turn: Double, side: Double) {
            self.travel = travel
            self.reach = reach
            self.rungs = rungs
            self.turn = turn
            self.side = side
        }

        /// The helix's motion clock at a moment of the light's presentation.
        static func motionSeconds(atPresentation elapsed: Double, reduceMotion: Bool) -> Double {
            WelcomeLightMotionClock.time(
                WelcomeLightEntrance.Frame(elapsed: elapsed, reduceMotion: reduceMotion).flowElapsed)
        }

        /// - Parameter startSeconds: The helix's motion clock when the
        ///   arrival began, so its alignment stays fixed throughout.
        init(elapsed: Double, distance: Double, startSeconds: Double = 0, reduceMotion: Bool = false) {
            let time = elapsed - Self.delay
            let t = reduceMotion ? 1 : min(max(time / Self.flight, 0), 1)
            // Whipped in off the edges, slowing to rest as it winds into place.
            let remaining = pow(1 - t, 2.5)
            reach = distance
            // Far enough that the whole strand starts past the screen edge.
            let start = 2 + (WelcomeLightHelix.inletLength(reach: distance) + 0.3)
                / (WelcomeLightHelix.halfHeight * WelcomeLightHelix.inletPace)
            travel = start * remaining
            rungs = reduceMotion ? 1 : min(max((time - Self.rungsStart) / Self.rungsDuration, 0), 1)

            // Turn the helix by at most a quarter turn so that, halfway
            // through the flight, the backbones leave the tip straight to the
            // sides. The spin keeps going, so it stays near sideways
            // throughout the flight.
            let middle = WelcomeLightHelix.twist * WelcomeLightHelix.halfHeight
                + WelcomeLightHelix.spin * (startSeconds + Self.delay + Self.flight * 0.5)
            let offset = Double.pi / 2 - middle
            let alignment = offset - Double.pi * (offset / Double.pi).rounded()
            side = sin(middle + alignment) >= 0 ? 1 : -1
            // Hold the alignment while the strands are visibly on their
            // inlets, then ease it out into the ordinary spin.
            let releaseStart = Self.flight * 0.55
            let release = min(max((time - releaseStart) / (Self.duration - releaseStart), 0), 1)
            let hold = 1 - release * release * release * (release * (release * 6 - 15) + 10)
            turn = reduceMotion ? 0 : alignment * hold
        }

        /// Growth of the base pair centred at `height` (-1...1): the middle
        /// pairs are laid first, the ones near the tips last.
        func rungGrowth(height: Double) -> Double {
            let k = min(max(rungs * 1.5 - 0.5 * abs(height), 0), 1)
            return k * k * k * (k * (k * 6 - 15) + 10)
        }
    }

    /// Both ends advance along the helical path at the same constant speed.
    /// The soft lower end travels with the upper one, preserving the height
    /// of the helix until the screen clips it. No supply is added below it.
    enum Departure {
        static let rise = 4.2

        static func top(_ exit: Double) -> Double { -halfHeight - rise * exit }
        static func tail(_ exit: Double) -> Double { halfHeight - rise * exit }

        static func axial(height: Double, exit: Double) -> Double {
            height * halfHeight - rise * exit
        }
    }

    static func climb(height: Double) -> Double {
        if height >= -1 { return acos(min(max(sin(height * asin(0.995)) / 0.995, -1), 1)) }
        return Double.pi + (-1 - height) * Double.pi * 0.5
    }

    static func heightAt(climb: Double) -> Double {
        climb <= Double.pi ? height(phase: climb) : -1 - (climb - Double.pi) * 2 / Double.pi
    }

    /// Position along the axis from -1 to 1, travelling the full length and
    /// back once per loop with an even pace between the ends.
    static func height(phase: Double) -> Double {
        asin(0.995 * cos(phase)) / asin(0.995)
    }

    /// Narrows the helix only near its ends, where both backbones meet.
    static func envelope(height: Double) -> Double {
        sqrt(max(0, 1 - pow(abs(height), 4)))
    }

    /// Control points of an inlet relative to the bottom tip, for the
    /// backbone that comes in from the right (`side` 1) or left (-1).
    private static func inletControls(reach: Double, side: Double) -> [CGPoint] {
        // Leaves the tip horizontally to meet the tapered helical arc without a kink.
        [CGPoint(x: 0, y: 0), CGPoint(x: side * 0.2, y: 0),
         CGPoint(x: side * reach * 0.55, y: 0.55), CGPoint(x: side * reach, y: 1.15)]
    }

    /// Approximate arc length of an inlet, shared with the shader.
    static func inletLength(reach: Double) -> Double {
        let c = inletControls(reach: reach, side: 1)
        func d(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(b.x - a.x, b.y - a.y) }
        return (d(c[0], c[1]) + d(c[1], c[2]) + d(c[2], c[3]) + d(c[0], c[3])) / 2
    }

    /// Offset from the bottom tip of a strand point that is still `excess`
    /// helix height out along its inlet. The bundle fans out as it leaves
    /// the tip, so the incoming strand reads as loose silk.
    static func inletOffset(excess: Double, side: Double, lane: Double, sheet: Double, reach: Double, seconds: Double) -> CGPoint {
        let c = inletControls(reach: reach, side: side)
        let length = inletLength(reach: reach)
        let s = excess * halfHeight * inletPace
        let t = min(s / length, 1)
        let v = 1 - t
        var x = v * v * v * c[0].x + 3 * v * v * t * c[1].x + 3 * v * t * t * c[2].x + t * t * t * c[3].x
        var y = v * v * v * c[0].y + 3 * v * v * t * c[1].y + 3 * v * t * t * c[2].y + t * t * t * c[3].y
        var dx = 3 * v * v * (c[1].x - c[0].x) + 6 * v * t * (c[2].x - c[1].x) + 3 * t * t * (c[3].x - c[2].x)
        var dy = 3 * v * v * (c[1].y - c[0].y) + 6 * v * t * (c[2].y - c[1].y) + 3 * t * t * (c[3].y - c[2].y)
        let magnitude = max(hypot(dx, dy), 1e-6)
        dx /= magnitude
        dy /= magnitude
        // Past the end it carries straight on, out of frame.
        let beyond = max(s - length, 0)
        x += dx * beyond
        y += dy * beyond
        let fan = min(max(s / 0.35, 0), 1)
        let spread = fan * fan * (3 - 2 * fan)
            * (lane * 0.05 + (sheet - 1) * 0.025 + 0.012 * sin(9 * s + lane * 2.4 - 1.7 * seconds + sheet * 2))
        return CGPoint(x: x - dy * spread, y: y + dx * spread)
    }

    static func point(u: Double, ring: Int, strand: Int, seconds: Double, arrival: Arrival = .settled, exit: Double = 0) -> (point: CGPoint, depth: Double) {
        let sheet = strand / 20
        let laneIndex = strand % 20
        let lane = Double(laneIndex) / 19 * 2 - 1
        let ringValue = Double(ring)
        let sheetValue = Double(sheet)
        let original = (u + 0.5) * WelcomeLightGeometry.tau
        var phase = original
        // While a backbone is pulled in, each of its points sits further back
        // along its own path: lower down the helix, or out on the inlet.
        var excess = 0.0
        if sheet != 1 && arrival.travel > 0 {
            let shifted = height(phase: original) + arrival.travel
            let clamped = min(shifted, 1)
            excess = shifted - clamped
            let c = min(max(sin(clamped * asin(0.995)) / 0.995, -1), 1)
            phase = sin(original) < -1e-6 ? -acos(c) : acos(c)
        }
        let h = height(phase: phase)
        let traveling = Departure.axial(height: h, exit: exit)
        let axial = traveling
        let endDistance = min(max(min(axial - Departure.top(exit), Departure.tail(exit) - axial) / halfHeight, 0), 1)
        let envelope = sqrt(max(0, 1 - pow(1 - endDistance, 4)))
        let turn = twist * axial + spin * seconds
        // A slow swell travels up the helix, so it breathes like the heart.
        let swell = 1 + 0.03 * sin(2.2 * axial - 0.9 * seconds)
        let seed = Double(strand) * 1.37 + ringValue * 4.1
        var y = axial
        var r: Double
        var theta: Double
        // Which backbone this point belongs to, and so which side its inlet
        // comes from; 0 only in the dissolved tips where they hand over.
        var backbone = 0.0
        if sheet == 1 {
            // Sweeps across the axis between the backbones, once per base pair.
            // Both passes over a pair are thin threads waving in opposite
            // directions, so together they read as a twisted double line.
            let offset = ring == 0 ? 0 : Double.pi / 2
            let rungClimb = climb(height: axial / halfHeight)
            let rungPhase = exit > 0 ? (sin(original) < -1e-6 ? WelcomeLightGeometry.tau - rungClimb : rungClimb) : phase
            let angle = rungsPerPass * rungPhase + offset
            // An even crossing speed gives every pair enough samples to wave
            // smoothly; the turns near the backbones are hidden by the shader.
            let sweep = sin(angle)
            let middle = 1 - sweep * sweep
            // Each pair lies level at the height where it crosses the axis;
            // between pairs the thread follows the backbone, hidden in it.
            let center = ((angle / Double.pi).rounded() * Double.pi - offset) / rungsPerPass
            let centerHeight = exit > 0 ? heightAt(climb: sin(original) < -1e-6 ? WelcomeLightGeometry.tau - center : center)
                : height(phase: center)
            let level = axial + (centerHeight * halfHeight - axial) * smoothstep(0, 0.3, middle)
            let pass = 1.4 * tanh(sin(phase) / 0.05)
            // Each pair grows out from the axis towards both backbones. Its
            // own level keeps the growth continuous where pairs hand over.
            let growth = arrival.rungGrowth(height: min(max(level / halfHeight, -1), 1))
            r = (radius - 0.02) * swell * sweep * envelope * growth
            theta = twist * level + spin * seconds + lane * 0.04 * middle
            y = level + lane * (0.0015 + 0.006 * middle * cos(4 * sweep + 0.9 * seconds + ringValue + pass)) * envelope
                + 0.02 * middle * sin(3.6 * sweep + 1.2 * seconds + pass * 1.1 + ringValue) * envelope
                + 0.006 * middle * sin(1.3 * seconds + 5 * level + ringValue * 2.1)
        } else {
            // Half a turn apart on the way up and on the way down. The swap
            // happens right at the tips, where the envelope has closed.
            let side = ring == 0 ? 1.0 : -1.0
            // Taken from the point's own place on the loop, so a strand keeps
            // its side while it slides past the tip into the helix.
            backbone = tanh(sin(original) / 0.03) * side
            let across = Double.pi / 2 * backbone
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
            let streaming = min(arrival.travel, 1)
            let foot = smoothstep(0, 0.12, 1 - axial / halfHeight)
            let taper = (0.35 + 0.65 * envelope) * (1 - streaming + streaming * foot)
            r = radius * swell * envelope + (offset * cos(torsion) + plyOffset * cos(ply)) * taper
            y += (offset * sin(torsion) + plyOffset * sin(ply)) * taper
            theta += lane * 0.05 * taper
            // The outermost thread of each sheet drifts free as a faint aura.
            if laneIndex == 19 {
                r += (0.04 + 0.025 * sin(2.3 * axial + 0.7 * seconds + ringValue * 2)) * envelope
            }
        }
        theta += arrival.turn
        let x = r * sin(theta), z = r * cos(theta)
        let perspective = 1 / (1 - z * 0.30)
        let near = min(max(y + Departure.rise * exit, -1.25), 1.25)
        let streaming = min(arrival.travel, 1)
        let footProjection = streaming * (1 - smoothstep(0, 0.2, halfHeight - axial))
        let projectedY = near * perspective + y - near
        var point = CGPoint(x: x * perspective, y: projectedY + (y - projectedY) * footProjection)
        if excess > 0 {
            // One backbone comes from the lower right, the other from the
            // lower left, each crossing the tip into the arc on the far side.
            let inlet = inletOffset(excess: excess, side: backbone * arrival.side, lane: lane, sheet: sheetValue,
                                    reach: arrival.reach, seconds: seconds)
            point.x += inlet.x
            point.y += inlet.y
        }
        return (point, (radius - z) * 0.8)
    }

    private static func smoothstep(_ from: Double, _ to: Double, _ value: Double) -> Double {
        let t = min(max((value - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
