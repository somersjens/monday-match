import Foundation

/// Periodic screen-speed compensation, fitted to projected native ribbon motion.
/// Positive phase speed preserves every pose and a continuous forward rotation.
enum WelcomeLightMotionClock {
    private static let harmonics: [SIMD2<Double>] = [
        SIMD2<Double>(0.002245705512, -0.007329286917),
        SIMD2<Double>(0.022521597573, -0.009195240480),
        SIMD2<Double>(0.001401578151, 0.002158614613),
        SIMD2<Double>(0.001996512288, -0.003464574573),
        SIMD2<Double>(0.001040135762, 0.002287272432)
    ]

    static func time(_ elapsed: Double) -> Double {
        let duration = WelcomeLightGeometry.duration
        let cycle = elapsed/duration
        let angle = (cycle-floor(cycle))*Double.pi*2
        var offset = 0.0
        for (index, coefficient) in harmonics.enumerated() {
            let phase = Double(index+1)*angle
            offset += coefficient.x*sin(phase)+coefficient.y*(1-cos(phase))
        }
        return elapsed+duration*offset
    }

    static func playbackTime(forPhase phase: Double) -> Double {
        var lower = 0.0, upper = WelcomeLightGeometry.duration
        for _ in 0..<48 {
            let middle = (lower+upper)*0.5
            if time(middle) < phase { lower = middle } else { upper = middle }
        }
        return (lower+upper)*0.5
    }
}
