import CoreGraphics
import Foundation

/// The helix rewoven into a personality model's chart. Coordinates are in
/// `WelcomeLightGeometry`'s normalized space (y grows downward), and the
/// Metal shader mirrors the layout functions here exactly, so the labels
/// drawn by SwiftUI land on the light.
enum WelcomeLightPersonality {
    static let morphDuration = 1.6
    /// From one chart straight into the next, without passing the helix.
    static let crossDuration = 1.3
    /// The shader receives three `float4`s per chart.
    static let maximumValues = 12

    /// Where every chart is centred, a little above the helix's middle.
    static let centerY = -0.05

    enum Kind: Int, Equatable {
        /// Rows with two poles and a bright bead where the user stands.
        case spectrum = 1
        /// A polygon over rings and spokes, one corner per trait.
        case radar = 2
        /// The enneagram's circle, triangle and hexad, with an orb per type.
        case enneagram = 3
        /// Four coloured quarters and an orb at the user's position.
        case wheel = 4
    }

    struct Visual: Equatable {
        var kind: Kind
        /// Spectrum: −1…1 per row, negative toward the left pole.
        /// Radar: 0…1 per corner, the first at the top, then clockwise.
        /// Enneagram: 0…1 for types 1 to 9, then the type and its wing.
        /// Wheel: the orb's x and y in −1…1 of the radius (y downward), then
        /// 0…1 for the top left, top right, bottom right and bottom left quarters.
        var values: [Double]

        init(kind: Kind, values: [Double]) {
            self.kind = kind
            self.values = Array(values.prefix(WelcomeLightPersonality.maximumValues))
        }
    }

    static var shaderConstants: String {
        "constant float chartCenterY = \(centerY), radarRadius = \(Radar.radius), "
            + "enneagramRadius = \(Enneagram.radius), wheelRadius = \(Wheel.radius);\n"
            + Spectrum.shaderConstants
    }

    enum Radar {
        static let radius = 0.70

        /// A corner at `fraction` of the radius, the first at the top.
        static func point(_ index: Int, count: Int, fraction: Double = 1) -> CGPoint {
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(count, 1))
            return CGPoint(x: cos(angle) * radius * fraction, y: sin(angle) * radius * fraction + centerY)
        }
    }

    enum Enneagram {
        static let radius = 0.70

        /// Type 9 sits at the top; the others follow clockwise.
        static func point(type: Int, fraction: Double = 1) -> CGPoint {
            let angle = 2 * Double.pi * Double(type % 9) / 9
            return CGPoint(x: sin(angle) * radius * fraction, y: -cos(angle) * radius * fraction + centerY)
        }
    }

    enum Wheel {
        static let radius = 0.70
    }

    enum Spectrum {
        static let halfWidth = 0.78
        static var centerY: Double { WelcomeLightPersonality.centerY }
        /// The distance between the first and last row's centres, at most.
        static let span = 1.44
        static let maximumSpacing = 0.46

        static func spacing(count: Int) -> Double {
            count > 1 ? min(maximumSpacing, span / Double(count - 1)) : 0
        }

        static func rowY(_ row: Int, count: Int) -> Double {
            (Double(row) - Double(count - 1) / 2) * spacing(count: count) + centerY
        }

        /// Where a row's bead sits along its bar.
        static func markerX(value: Double) -> Double {
            min(max(value, -1), 1) * halfWidth
        }

        static var shaderConstants: String {
            "constant float spectrumHalfWidth = \(halfWidth), spectrumCenterY = \(centerY), "
                + "spectrumSpan = \(span), spectrumMaxSpacing = \(maximumSpacing);"
        }
    }

    /// What the renderer draws this frame.
    struct Pose: Equatable {
        /// How far the helix has rewoven into the chart.
        var amount: Double
        /// Progress from `from` into `to`; 1 when only `to` shows.
        var cross: Double
        var from: Visual
        var to: Visual
    }

    /// Tracks the morph from the helix into a chart, between charts, and back,
    /// against any monotonic clock.
    struct Motion {
        private var current: Visual?
        private var previous: Visual?
        private var amountFrom = 0.0
        private var amountTo = 0.0
        private var amountStartedAt: Double?
        private var crossStartedAt: Double?

        mutating func update(_ visual: Visual?, now: Double, animated: Bool) {
            guard let visual else {
                guard amountTo != 0 else { return }
                amountFrom = amount(at: now)
                amountTo = 0
                amountStartedAt = animated ? now : nil
                return
            }
            let shown = amount(at: now)
            if current == nil || shown <= 0.001 {
                // Fresh from the helix: no previous chart to cross from.
                current = visual
                previous = visual
                crossStartedAt = nil
            } else if visual != current {
                // Half way through a cross, the chart nearer on screen is the one to leave.
                if cross(at: now) >= 0.5 { previous = current }
                current = visual
                crossStartedAt = animated ? now : nil
            }
            if amountTo != 1 {
                amountFrom = shown
                amountTo = 1
                amountStartedAt = animated ? now : nil
            }
        }

        func amount(at now: Double) -> Double {
            guard let amountStartedAt, now - amountStartedAt < morphDuration else { return amountTo }
            let t = max((now - amountStartedAt) / morphDuration, 0)
            return amountFrom + (amountTo - amountFrom) * t
        }

        func cross(at now: Double) -> Double {
            guard let crossStartedAt, now - crossStartedAt < crossDuration else { return 1 }
            return max((now - crossStartedAt) / crossDuration, 0)
        }

        func pose(at now: Double) -> Pose? {
            let amount = amount(at: now)
            guard amount > 0, let current else { return nil }
            return Pose(amount: amount, cross: cross(at: now), from: previous ?? current, to: current)
        }
    }
}
