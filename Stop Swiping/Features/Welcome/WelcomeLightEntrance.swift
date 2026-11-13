import Foundation
import CoreGraphics

/// One presentation clock feeds the entrance and then the existing periodic loop.
/// The loop's shape, light and particle clocks never reset at the handoff.
enum WelcomeLightEntrance {
    private static let launchDuration = 0.65
    // Heart-perimeter units per second: preserve the established visible pace.
    private static let headSpeed = 0.3634
    private static let offscreenAdvance = 0.40
    private static let approachDuration = 0.18
    static let traceDuration = (1+inletLength)/headSpeed+launchDuration*0.5-offscreenAdvance
    static let accelerationStart = traceDuration-0.75
    static let duration = traceDuration
    static var inletLength: Double { -Double(inletTravel[0]) }

    static let inletTravel: [Float] = {
        let frame = WelcomeLightGeometry.Frame(elapsed: 0)
        let point = WelcomeLightGeometry.contour(ring: 0, frame: frame)[WelcomeLightGeometry.entranceStartSample]
        let tip = CGPoint(x: point.position.x*frame.screenScale.width+frame.drift.x,
                          y: point.position.y*frame.screenScale.height+frame.drift.y)
        let tangent = CGVector(dx: point.normal.dy, dy: -point.normal.dx)
        let points = (0...128).map { inletPoint(Double($0)/128, tip: tip, tangent: tangent, strand: 6) }
        var distances = [Double](repeating: 0, count: points.count)
        for index in 1..<points.count {
            distances[index] = distances[index-1] + hypot(points[index].x-points[index-1].x,
                                                         points[index].y-points[index-1].y)
        }
        let length = distances[128]
        // Same arc-distance unit on both paths: the head crosses the join
        // without changing speed as it reaches the heart's right flank.
        return distances.map { Float(($0-length)/WelcomeLightGeometry.heartPerimeter) }
    }()

    struct Frame {
        let loopElapsed: Double
        let flowElapsed: Double
        let streamStrength: Double
        let reveal: Double
        let inletOpacity: Double
        let headGlow: Double
        let dustOpacity: Double

        init(elapsed: Double, reduceMotion: Bool = false) {
            if reduceMotion {
                loopElapsed = WelcomeLightGeometry.heartTime
                flowElapsed = WelcomeLightGeometry.heartTime
                streamStrength = 0
                reveal = 2
                inletOpacity = 0
                headGlow = 0
                dustOpacity = 1
                return
            }
            let time = max(0, elapsed)
            let rampDuration = duration-accelerationStart
            let ramp = min(max((time-accelerationStart)/rampDuration, 0), 1)
            // Integral of smootherstep: velocity rises from 0 to 1, with zero
            // acceleration at both ends. Position and velocity match the loop.
            let integratedSpeed = pow(ramp, 6) - 3*pow(ramp, 5) + 2.5*pow(ramp, 4)
            loopElapsed = rampDuration*integratedSpeed + max(0, time-duration)
            // Material moves even while the heart's overall pose stays forward.
            // At handoff this clock has the same position and speed as the loop.
            flowElapsed = time-duration+rampDuration*0.5
            // All entrance-only motion is gone at closure, not afterwards.
            streamStrength = time >= traceDuration ? 0
                : ease(time/0.20)*(1-ease((time-(traceDuration-0.80))/0.80))
            // Accelerate once, then keep the head moving through closure. There
            // is no ease-out or stopped head at the bottom of the heart.
            // Compress only the hidden approach. The time offset settles before
            // the head crosses the screen edge, at the established visible pace.
            let flightTime = time+offscreenAdvance*ease(time/approachDuration)
            let launch = min(flightTime/launchDuration, 1)
            let launchedDistance = launchDuration*(pow(launch,6)-3*pow(launch,5)+2.5*pow(launch,4))
                + max(0,flightTime-launchDuration)
            // Start at the actual offscreen end, including the soft leading
            // glow. The visible speed and seamless handoff stay unchanged.
            reveal = -inletLength+headSpeed*launchedDistance
            inletOpacity = ease(time/0.20)*(1-ease((time-(traceDuration-0.16))/0.16))
            // Dissolve the leading light into the silk before the loop closes,
            // rather than carrying a bright ball around the completed heart.
            headGlow = 1-ease((reveal-0.65)/0.32)
            dustOpacity = ease((time-0.15)/1.25)
        }
    }

    /// The same normalized inlet curve is used by Metal and the Canvas fallback.
    /// Its last handle extends the right flank diagonally out of the frame.
    /// The string never bends around a separate corner at the bottom tip.
    static func inletPoint(_ t: Double, tip: CGPoint, tangent: CGVector, strand: Int, transport: Double = 0) -> CGPoint {
        let magnitude = max(hypot(tangent.dx, tangent.dy), 0.0001)
        let start = CGPoint(x: -1.65, y: 1.95)
        let c1 = CGPoint(x: -0.95, y: 1.45)
        let c2 = CGPoint(x: tip.x-tangent.dx/magnitude*0.65, y: tip.y-tangent.dy/magnitude*0.65)
        let v = 1-t
        let lane = Double(strand % 20)/19*2-1
        let sheet = (strand % WelcomeLightGeometry.strandCount)/20
        let ring = strand/WelcomeLightGeometry.strandCount
        let phase = Double(sheet)*2.15+Double(ring)*1.7+lane*0.85
        let flow = t*WelcomeLightGeometry.tau*1.4-transport*WelcomeLightGeometry.tau*2+phase
        // Use the same sheet/lane structure as the heart: broad, crossing silk
        // with separated fine threads rather than a tightly packed cable.
        let cross = 0.065*sin(flow)+lane*0.055*cos(t*WelcomeLightGeometry.tau+phase)
            + 0.020*sin(2*flow+phase)
        let along = 0.025*sin(t*WelcomeLightGeometry.tau*2-transport*WelcomeLightGeometry.tau*2+phase)
        let dx = 3*v*v*(c1.x-start.x)+6*v*t*(c2.x-c1.x)+3*t*t*(tip.x-c2.x)
        let dy = 3*v*v*(c1.y-start.y)+6*v*t*(c2.y-c1.y)+3*t*t*(tip.y-c2.y)
        let length = max(hypot(dx,dy),0.0001)
        // Both value and derivative vanish at the join. Individual filaments
        // inherit the heart's spread and tangent without a visible seam.
        let veil = pow(4*t*(1-t),2)
        return CGPoint(
            x: v*v*v*start.x+3*v*v*t*c1.x+3*v*t*t*c2.x+t*t*t*tip.x
                + veil*(-dy*cross+dx*along)/length,
            y: v*v*v*start.y+3*v*v*t*c1.y+3*v*t*t*c2.y+t*t*t*tip.y
                + veil*(dx*cross+dy*along)/length
        )
    }

    private static func ease(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t*t*t*(t*(t*6-15)+10)
    }
}
