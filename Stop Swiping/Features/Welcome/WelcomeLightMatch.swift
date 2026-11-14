import Foundation
import CoreGraphics

/// The match animation. The helix winds upward at a constant speed, with
/// both ends travelling together and the lower end fading softly, as if
/// sent to the other phone. It comes back from above as the match heart: each ring is one
/// open strand that falls in from above, crosses at the top cusp into the
/// opposite lobe, crosses again at the tip and runs on under the opposite
/// score. Without a match the finished heart cracks and its halves part.
///
/// Geometry lives in the shader (`matchPath`); positions here are in the same
/// normalized space, for the SwiftUI labels around the heart.
enum WelcomeLightMatch {
    enum Transition: Equatable {
        case newMatch
        case savedMatch

        static let savedMorphDuration = 2.2

        /// Saved results pull the finite coil into the cusp and along the lobes.
        func time(_ newMatchTime: Double, isMatch: Bool = true) -> Double {
            guard self == .savedMatch else { return newMatchTime }
            if newMatchTime >= heartEnd { return Self.savedMorphDuration + newMatchTime - heartEnd }
            let head = WelcomeLightMatch.head(at: newMatchTime)
            let advance = Route.advance(for: head, isMatch: isMatch)
            let travel = 1 - pow(1 - advance, 1 / 1.8)
            return Self.savedMorphDuration * travel
        }
    }

    /// The heart starts at the existing helix tip. Their shared frame then
    /// settles downward during the morph, with no separate alignment beat.
    static func sharedOffset(progress: Double, layout: Layout) -> Double {
        let t = clamp(progress)
        let drift = t*t*t*(t*(t*6 - 15) + 10)
        let cuspY = -0.62 * layout.scale + layout.offsetY
        return (-WelcomeLightHelix.halfHeight - cuspY) * (1 - drift)
    }

    /// Arc distance along the existing heart outline. Swift label timing and
    /// Metal material transport share these tables, including the cusp speed.
    enum Route {
        static let intervals = 256

        private static func point(_ s: Double, layout: Layout) -> CGPoint {
            let scale = layout.scale, y = layout.offsetY
            func p(_ x: Double, _ h: Double) -> CGPoint { CGPoint(x: x * scale, y: h * scale + y) }
            let a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint, t: Double
            if s < 0.504 {
                a = p(0, -0.62); b = p(0, -0.76); c = p(0.22, -0.88); d = p(0.48, -0.88)
                t = (s - cuspS) / (0.504 - cuspS)
            } else if s < 0.623 {
                a = p(0.48, -0.88); b = p(0.80, -0.88); c = p(0.98, -0.62); d = p(0.97, -0.30)
                t = (s - 0.504) / (0.623 - 0.504)
            } else if s < tipS {
                a = p(0.97, -0.30); b = p(0.96, 0.05); c = p(0.18, 0.56); d = p(0, 0.80)
                t = (s - 0.623) / (tipS - 0.623)
            } else {
                a = p(0, 0.80); b = p(-0.12, 0.96)
                c = CGPoint(x: -0.45 * scale, y: layout.lineY)
                d = CGPoint(x: -1.12 * scale, y: layout.lineY)
                t = min((s - tipS) / (1 - tipS), 1)
            }
            let v = 1 - t
            let q = CGPoint(x: v*v*v*a.x + 3*v*v*t*b.x + 3*v*t*t*c.x + t*t*t*d.x,
                            y: v*v*v*a.y + 3*v*v*t*b.y + 3*v*t*t*c.y + t*t*t*d.y)
            return CGPoint(x: q.x - max(0, s - 1) * 7, y: q.y)
        }

        private static func lengths(_ layout: Layout) -> [Double] {
            let points = (0...intervals).map { point(cuspS + (1.04 - cuspS) * Double($0) / Double(intervals), layout: layout) }
            var result = [0.0]
            for i in 1...intervals {
                result.append(result[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
            }
            return result
        }

        static let matchLengths = lengths(.match)
        static let noMatchLengths = lengths(.noMatch)

        static func values(isMatch: Bool) -> [Double] { isMatch ? matchLengths : noMatchLengths }

        static func speedRatio(isMatch: Bool) -> Double { 2 * WelcomeLightHelix.halfHeight / values(isMatch: isMatch).last! }

        static func head(advance: Double, isMatch: Bool) -> Double {
            let table = values(isMatch: isMatch), a = speedRatio(isMatch: isMatch)
            let distance = (a * advance + (1 - a) * advance * advance) * table.last!
            let high = table.firstIndex(where: { $0 >= distance }) ?? intervals
            guard high > 0 else { return cuspS }
            let fraction = (distance - table[high - 1]) / (table[high] - table[high - 1])
            return cuspS + (1.04 - cuspS) * (Double(high - 1) + fraction) / Double(intervals)
        }

        static func advance(for head: Double, isMatch: Bool) -> Double {
            let table = values(isMatch: isMatch), a = speedRatio(isMatch: isMatch)
            let sample = min(max((head - cuspS) / (1.04 - cuspS), 0), 1) * Double(intervals)
            let low = min(Int(sample), intervals - 1), fraction = sample - Double(low)
            let distance = (table[low] + fraction * (table[low + 1] - table[low])) / table.last!
            return min(max(2 * distance / (a + sqrt(a*a + 4*(1 - a)*distance)), 0), 1)
        }

        static func shaderLengths(isMatch: Bool) -> String {
            values(isMatch: isMatch).map { String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), $0) }.joined(separator: ", ")
        }
    }

    struct Request: Equatable {
        let id: UUID
        let isMatch: Bool
        var transition: Transition = .newMatch
        /// The conversation is open: the heart's tip pulls up until each lobe
        /// is a ring, and the two rings keep circling each other.
        var isChatting = false
    }

    /// Heart to rings for the conversation. The tip rises first, the strand
    /// that ran under the scores is drawn up into the rings, and once they
    /// are closed the pair starts to turn around its middle, slowly at first.
    enum Chat {
        static let morphDuration = 2.6
        /// When the turning starts, and how long it takes to reach full speed.
        static let orbitStart = 1.8
        static let orbitRamp = 2.6
        /// One full turn of the pair, in seconds.
        static let orbitPeriod = 9.0

        static func progress(elapsed: Double, reduceMotion: Bool = false) -> Double {
            if reduceMotion { return 1 }
            let t = min(max(elapsed / morphDuration, 0), 1)
            return t*t*t*(t*(t*6 - 15) + 10)
        }

        /// The pair's turn in radians. Speed eases in from rest, so the rings
        /// leave the heart's pose without a jolt.
        static func orbitAngle(elapsed: Double, reduceMotion: Bool = false) -> Double {
            if reduceMotion { return 0 }
            let speed = 2 * Double.pi / orbitPeriod
            let t = elapsed - orbitStart
            guard t > 0 else { return 0 }
            if t < orbitRamp {
                // ∫ smoothstep: x³ − x⁴/2.
                let x = t / orbitRamp
                return speed * orbitRamp * (x*x*x - x*x*x*x / 2)
            }
            return speed * (orbitRamp / 2 + t - orbitRamp)
        }

        /// The middle of the rings, in the light's normalized space.
        static let ringCenterY = -0.40
        static let ringCenterX = 0.48
        static let ringRadius = 0.47
    }

    /// Where the heart and the line between the scores sit.
    struct Layout: Equatable {
        let scale: Double
        let offsetY: Double
        let lineY: Double

        static let match = Layout(scale: 1, offsetY: 0, lineY: 1.02)
        /// Smaller and higher, leaving room for the reasons below.
        static let noMatch = Layout(scale: 0.78, offsetY: -0.34, lineY: 0.50)

        static func of(isMatch: Bool) -> Layout { isMatch ? .match : .noMatch }

        /// The middle of the heart's open space, for the average score.
        var heartCenterY: Double { offsetY - 0.17 * scale }
        var topY: Double { offsetY - 0.88 * scale }
    }

    /// Path positions where the strand crosses the top cusp and the tip.
    static let cuspS = 0.42
    static let tipS = 0.826
    /// Where the score labels sit, left and right of the tip.
    static let scoreX = 0.70

    static let exitDuration = 1.6
    static let heartDuration = 2.6
    static var heartEnd: Double { exitDuration + heartDuration }
    static var breakStart: Double { heartEnd + 0.3 }
    static let breakDuration = 1.5

    struct Pose: Equatable {
        /// 0…1 while the helix winds up out of view; 1 once it has left.
        var exit: Double
        /// Path position of each strand's leading end.
        var head: Double
        /// Path position of each strand's trailing end.
        var tail: Double
        /// 0…1 as the heart cracks and its halves part.
        var breakAmount: Double
        /// Nil for the send-and-return animation; otherwise the in-place morph.
        var morph: Double? = nil

        static let hidden = Pose(exit: 0, head: 0, tail: 0, breakAmount: 0)
    }

    static func pose(elapsed: Double, isMatch: Bool, reduceMotion: Bool = false,
                     transition: Transition = .newMatch) -> Pose {
        if reduceMotion {
            return Pose(exit: 1, head: 1.04, tail: cuspS, breakAmount: isMatch ? 0 : 1,
                        morph: transition == .savedMatch ? 1 : nil)
        }
        if transition == .savedMatch {
            let progress = clamp(elapsed / Transition.savedMorphDuration)
            let advance = 1 - pow(1 - progress, 1.8)
            let head = Route.head(advance: advance, isMatch: isMatch)
            return Pose(exit: 0, head: head,
                        tail: cuspS,
                        breakAmount: isMatch ? 0 : clamp((elapsed - transition.time(breakStart, isMatch: isMatch)) / breakDuration),
                        morph: progress)
        }
        let exit = clamp(elapsed / exitDuration)
        let head = head(at: elapsed)
        let tail = cuspS * smoothstep(cuspS, 1.0, head)
        let breakAmount = isMatch ? 0 : clamp((elapsed - breakStart) / breakDuration)
        return Pose(exit: exit, head: head, tail: tail, breakAmount: breakAmount)
    }

    /// The strand comes in quickly from above and settles along the line.
    static func head(at elapsed: Double) -> Double {
        let k = clamp((elapsed - exitDuration) / heartDuration)
        return 1.04 * (1 - pow(1 - k, 1.8))
    }

    /// When the leading end reaches a path position.
    static func elapsed(forHead s: Double) -> Double {
        let fraction = min(max(s / 1.04, 0), 1)
        return exitDuration + heartDuration * (1 - pow(1 - fraction, 1 / 1.8))
    }

    /// The SwiftUI layer's beats, in seconds from the start.
    static var averageRevealTime: Double { elapsed(forHead: tipS) }
    static var scoresRevealTime: Double { elapsed(forHead: 0.96) }
    static func controlsRevealTime(isMatch: Bool) -> Double {
        isMatch ? heartEnd : breakStart + breakDuration * 0.8
    }
    static var issuesRevealTime: Double { breakStart + breakDuration * 0.45 }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        let t = clamp((value - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }
}
