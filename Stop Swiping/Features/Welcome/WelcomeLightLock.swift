import CoreGraphics
import Foundation

/// What the landing light's filaments are woven into.
enum WelcomeLightForm: Equatable {
    case heart
    case lock
    case helix
}

/// The padlock the heart's own filaments are rewoven into. The outer sheets
/// of both rings trace one connected silhouette, shackle and body together;
/// the first ring's blue sheet traces the opening under the shackle and the
/// second ring's blue sheet the keyhole. Coordinates match
/// `WelcomeLightGeometry`'s normalized space, and the Metal shader mirrors
/// these functions exactly.
enum WelcomeLightLock {
    static let morphDuration = 1.7

    static let bodyCenter = CGPoint(x: 0, y: 0.30)
    static let bodyHalfSize = CGSize(width: 0.70, height: 0.47)
    static let bodyCornerRadius = 0.18
    static let shackleCenter = CGPoint(x: 0, y: -0.44)
    static let shackleOuterRadius = 0.42
    static let shackleInnerRadius = 0.26
    /// Rounds the joints where the shackle's legs meet the body.
    static let jointRadius = 0.04
    static let keyholeCenter = CGPoint(x: 0, y: 0.22)
    static let keyholeRadius = 0.085
    static let keyholeTail = 0.20

    static var bodyTop: Double { bodyCenter.y - bodyHalfSize.height }

    struct Pose: Equatable {
        var amount: Double
        var lift: Double
        var shake: Double
        /// Weaves `WelcomeLightHelix` instead of the lock.
        var isHelix = false
        /// How far the helix has rewoven into `WelcomeLightCode`.
        var code = 0.0

        static let unlocked = Pose(amount: 0, lift: 0, shake: 0)
    }

    /// A tug on the shackle and a short shake, decaying within a second.
    static func pulse(elapsed: Double) -> (lift: Double, shake: Double) {
        guard elapsed >= 0, elapsed < 1.6 else { return (0, 0) }
        let lift = 0.055 * exp(-6 * elapsed) * sin(20 * elapsed)
        let shake = 0.03 * exp(-7 * elapsed) * sin(36 * elapsed)
        return (lift, shake)
    }

    static func ease(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    static func outline(u: Double, ring: Int, sheet: Int) -> CGPoint {
        guard sheet == 1 else { return silhouette(u) }
        return ring == 0 ? opening(u) : keyhole(u)
    }

    /// The padlock's outer contour: the shackle's arch flowing down into the
    /// body without a seam. It starts at the crown and runs anticlockwise on
    /// screen, like the heart's contour.
    static func silhouette(_ u: Double) -> CGPoint { evaluate(silhouetteSegments, at: u) }

    /// The space enclosed by the shackle and the top of the body.
    static func opening(_ u: Double) -> CGPoint { evaluate(openingSegments, at: u) }

    /// A circle drawn down into a tapering slot, smooth all the way round.
    static func keyhole(_ u: Double) -> CGPoint {
        let angle = wrap(u) * WelcomeLightGeometry.tau
        let s = sin(angle), c = cos(angle)
        let tail = pow(max(0, -c), 6)
        return CGPoint(
            x: keyholeCenter.x - s * keyholeRadius * (1 - 0.55 * tail),
            y: keyholeCenter.y - c * keyholeRadius + tail * keyholeTail
        )
    }

    /// How much of a point belongs to the shackle, which lifts and floats on
    /// its own while the body stays put.
    static func shackleWeight(y: Double) -> Double {
        let t = min(max((y - (bodyTop - 0.18)) / 0.18, 0), 1)
        return 1 - t * t * (3 - 2 * t)
    }

    /// One filament's position on the lock, including its weave and the
    /// lock's slow breathing.
    static func point(u: Double, ring: Int, strand: Int, seconds: Double, pose: Pose) -> CGPoint {
        let sheet = strand / 20
        let lane = Double(strand % 20) / 19 * 2 - 1
        // The opening and keyhole are inner details, drawn as finer lines.
        let detail = sheet == 1
        let base = outline(u: u, ring: ring, sheet: sheet)
        let ahead = outline(u: u + 0.002, ring: ring, sheet: sheet)
        let behind = outline(u: u - 0.002, ring: ring, sheet: sheet)
        let dx = ahead.x - behind.x, dy = ahead.y - behind.y
        let length = max(hypot(dx, dy), 1e-7)
        let normal = CGVector(dx: -dy / length, dy: dx / length)
        let angle = u * WelcomeLightGeometry.tau
        let phase = Double(sheet) * 2.1 + Double(ring) * 1.3
        let width = detail ? 0.010 : 0.020
        let weave = (detail ? 0.005 : 0.016) * sin(4 * angle + phase - seconds * 0.9)
            + (detail ? 0.002 : 0.006) * sin(7 * angle - phase + seconds * 1.4)
        let offset = lane * width + weave + (detail ? 0 : (Double(sheet) - 1) * 0.010)
        var x = base.x + normal.dx * offset
        var y = base.y + normal.dy * offset
        y -= (pose.lift + 0.010 * sin(seconds * 1.1)) * shackleWeight(y: base.y)
        let breathe = 1 + 0.012 * sin(seconds * 1.3)
        x *= breathe * cos(0.10 * sin(seconds * 0.55))
        y *= breathe
        return CGPoint(x: x + pose.shake, y: y)
    }

    /// Strands depart at slightly different moments, so the shape re-forms
    /// as travelling silk rather than a uniform crossfade.
    static func strandAmount(_ amount: Double, u: Double, instance: Int) -> Double {
        guard amount > 0 else { return 0 }
        let stagger = 0.35 * (0.5 + 0.5 * sin(u * WelcomeLightGeometry.tau + Double(instance) * 0.37))
        return ease(amount * 1.35 - stagger)
    }

    /// Tracks the morph between the heart and the lock or helix against any
    /// monotonic clock.
    struct Motion {
        private var form: WelcomeLightForm?
        /// What a nonzero amount weaves; kept while morphing back to the heart.
        private var shape = WelcomeLightForm.lock
        private var from = 0.0
        private var to = 0.0
        private var startedAt: Double?
        private var pulseAt: Double?
        private var lastPulse = 0
        private var codeFrom = 0.0
        private var codeTo = 0.0
        private var codeStartedAt: Double?

        mutating func update(isLocked locked: Bool, pulse: Int, now: Double, animated: Bool) {
            update(form: locked ? .lock : .heart, pulse: pulse, now: now, animated: animated)
        }

        /// The first update adopts the state without a morph, so a locked
        /// landing page opens already locked. The helix never grows out of
        /// the heart: it appears whole, and the view brings it into frame.
        mutating func update(form newForm: WelcomeLightForm, pulse: Int, now: Double, animated: Bool) {
            guard let current = form else {
                form = newForm
                if newForm != .heart { shape = newForm }
                from = newForm == .heart ? 0 : 1
                to = from
                lastPulse = pulse
                return
            }
            if newForm != current {
                var start = progress(at: now)
                if newForm != .heart {
                    // Lock and helix never blend into each other; a switch
                    // between them re-forms from the heart.
                    if newForm != shape { start = 0 }
                    shape = newForm
                }
                form = newForm
                from = start
                to = newForm == .heart ? 0 : 1
                startedAt = animated && newForm != .helix ? now : nil
                // The shackle settles with a small click once it closes.
                pulseAt = animated && newForm == .lock ? now + morphDuration * 0.82 : nil
            }
            if pulse != lastPulse {
                lastPulse = pulse
                pulseAt = animated ? now : nil
            }
        }

        /// Only the helix turns into the code; any other form drops it.
        mutating func update(showsCode: Bool, now: Double, animated: Bool) {
            let target = showsCode ? 1.0 : 0.0
            guard target != codeTo else { return }
            codeFrom = codeProgress(at: now)
            codeTo = target
            codeStartedAt = animated ? now : nil
        }

        func codeProgress(at now: Double) -> Double {
            guard let codeStartedAt, now - codeStartedAt < WelcomeLightCode.morphDuration else { return codeTo }
            let t = max((now - codeStartedAt) / WelcomeLightCode.morphDuration, 0)
            return codeFrom + (codeTo - codeFrom) * t
        }

        func progress(at now: Double) -> Double {
            guard let startedAt, now - startedAt < morphDuration else { return to }
            let t = max((now - startedAt) / morphDuration, 0)
            return from + (to - from) * t
        }

        func pose(at now: Double) -> Pose {
            let amount = progress(at: now)
            guard amount > 0 else { return .unlocked }
            let jiggle = pulseAt.map { WelcomeLightLock.pulse(elapsed: now - $0) } ?? (lift: 0, shake: 0)
            let isHelix = shape == .helix
            return Pose(amount: amount, lift: jiggle.lift, shake: jiggle.shake, isHelix: isHelix,
                        code: isHelix ? codeProgress(at: now) : 0)
        }

        func isAnimating(at now: Double) -> Bool {
            let morphing = startedAt.map { now - $0 < morphDuration } ?? false
            let pulsing = pulseAt.map { now - $0 < 1.6 } ?? false
            let coding = codeStartedAt.map { now - $0 < WelcomeLightCode.morphDuration } ?? false
            return morphing || pulsing || coding
        }
    }

    private enum Segment {
        case line(CGPoint, CGPoint)
        case arc(center: CGPoint, radius: Double, from: Double, to: Double)

        var length: Double {
            switch self {
            case let .line(a, b): hypot(b.x - a.x, b.y - a.y)
            case let .arc(_, radius, from, to): radius * abs(to - from)
            }
        }

        func point(_ t: Double) -> CGPoint {
            switch self {
            case let .line(a, b):
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            case let .arc(center, radius, from, to):
                let angle = from + (to - from) * t
                return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            }
        }
    }

    private static let silhouetteSegments: [Segment] = {
        let c = shackleCenter, R = shackleOuterRadius, j = jointRadius, r = bodyCornerRadius
        let top = bodyTop, bottom = bodyCenter.y + bodyHalfSize.height
        let side = bodyHalfSize.width, corner = side - r
        return [
            .arc(center: c, radius: R, from: -.pi / 2, to: -.pi),
            .line(CGPoint(x: -R, y: c.y), CGPoint(x: -R, y: top - j)),
            .arc(center: CGPoint(x: -R - j, y: top - j), radius: j, from: 0, to: .pi / 2),
            .line(CGPoint(x: -R - j, y: top), CGPoint(x: -corner, y: top)),
            .arc(center: CGPoint(x: -corner, y: top + r), radius: r, from: -.pi / 2, to: -.pi),
            .line(CGPoint(x: -side, y: top + r), CGPoint(x: -side, y: bottom - r)),
            .arc(center: CGPoint(x: -corner, y: bottom - r), radius: r, from: .pi, to: .pi / 2),
            .line(CGPoint(x: -corner, y: bottom), CGPoint(x: corner, y: bottom)),
            .arc(center: CGPoint(x: corner, y: bottom - r), radius: r, from: .pi / 2, to: 0),
            .line(CGPoint(x: side, y: bottom - r), CGPoint(x: side, y: top + r)),
            .arc(center: CGPoint(x: corner, y: top + r), radius: r, from: 0, to: -.pi / 2),
            .line(CGPoint(x: corner, y: top), CGPoint(x: R + j, y: top)),
            .arc(center: CGPoint(x: R + j, y: top - j), radius: j, from: .pi / 2, to: .pi),
            .line(CGPoint(x: R, y: top - j), CGPoint(x: R, y: c.y)),
            .arc(center: c, radius: R, from: 0, to: -.pi / 2),
        ]
    }()

    private static let openingSegments: [Segment] = {
        let c = shackleCenter, a = shackleInnerRadius, j = jointRadius, top = bodyTop
        return [
            .arc(center: c, radius: a, from: -.pi / 2, to: -.pi),
            .line(CGPoint(x: -a, y: c.y), CGPoint(x: -a, y: top - j)),
            .arc(center: CGPoint(x: -a + j, y: top - j), radius: j, from: .pi, to: .pi / 2),
            .line(CGPoint(x: -a + j, y: top), CGPoint(x: a - j, y: top)),
            .arc(center: CGPoint(x: a - j, y: top - j), radius: j, from: .pi / 2, to: 0),
            .line(CGPoint(x: a, y: top - j), CGPoint(x: a, y: c.y)),
            .arc(center: c, radius: a, from: 0, to: -.pi / 2),
        ]
    }()

    private static func evaluate(_ segments: [Segment], at u: Double) -> CGPoint {
        let lengths = segments.map(\.length)
        var distance = wrap(u) * lengths.reduce(0, +)
        for (segment, length) in zip(segments, lengths).dropLast() {
            if distance <= length { return segment.point(distance / length) }
            distance -= length
        }
        return segments[segments.count - 1].point(min(distance / lengths[lengths.count - 1], 1))
    }

    private static func wrap(_ u: Double) -> Double { u - floor(u) }
}
