import Foundation
import CoreGraphics

/// Geometry in normalized coordinates, shared by the renderer and continuity tests.
enum WelcomeLightGeometry {
    static let duration = 6.042
    static let tau = Double.pi * 2
    static let sampleCount = 512
    static let strandCount = 60
    // Join on the long lower-right flank, avoiding the tight bottom turn.
    static let entranceStartSample = sampleCount/2 + 3*sampleCount/32
    static var entranceStartU: Double { Double(entranceStartSample)/Double(sampleCount) }
    static let heartTime = 0.0
    private static let referenceCircleTime = 2.52
    static let circleTime = WelcomeLightMotionClock.playbackTime(forPhase: referenceCircleTime)

    /// Sparse poses measured against the reference, not sampled video frames.
    /// Rotation, width, vertical size and depth follow separate timelines.
    private struct Pose {
        let time: Double
        let values: [Double]
    }

    // Heart, separation, radius x/y, depth, drift x/y.
    // These shape poses blend back while rotation and ribbon flow keep advancing.
    private static let poses: [Pose] = [
        Pose(time: 0, values: [1, 0, 0.82, 0.60, 0.19, 0, -0.02]),
        Pose(time: 0.25, values: [1, 0, 0.82, 0.60, 0.19, 0, -0.02]),
        Pose(time: 0.50, values: [0.98, 0, 0.82, 0.60, 0.20, 0, -0.02]),
        Pose(time: 0.76, values: [0.91, 0.02, 0.80, 0.61, 0.21, 0.01, -0.02]),
        Pose(time: 1.01, values: [0.73, 0.08, 0.76, 0.61, 0.23, 0.055, -0.03]),
        Pose(time: 1.26, values: [0.45, 0.17, 0.66, 0.61, 0.22, 0.085, -0.04]),
        Pose(time: 1.51, values: [0.16, 0.30, 0.57, 0.61, 0.19, 0.08, -0.04]),
        Pose(time: 1.76, values: [0.04, 0.39, 0.52, 0.61, 0.16, 0.07, -0.04]),
        Pose(time: 2.01, values: [0, 0.44, 0.52, 0.60, 0.12, 0.04, -0.03]),
        Pose(time: 2.27, values: [0, 0.48, 0.52, 0.60, 0.10, 0.02, -0.03]),
        Pose(time: 2.52, values: [0, 0.48, 0.52, 0.60, 0.09, 0, -0.03]),
        Pose(time: 2.77, values: [0, 0.43, 0.55, 0.60, 0.10, -0.01, -0.03]),
    ]

    // Sparse projected bounds measured against the reference at 0.252 s intervals.
    // These are geometric scales/drifts, never stored pixels or frames.
    private static let calibration: [Pose] = [
        Pose(time: 0.000000, values: [0.946779, 0.965512, 0.023919, 0.026493]),
        Pose(time: 0.251750, values: [0.873529, 1.018248, -0.076967, 0.046983]),
        Pose(time: 0.503500, values: [0.906615, 1.000000, -0.125785, 0.091991]),
        Pose(time: 0.755250, values: [1.000000, 0.975089, -0.091991, 0.054864]),
        Pose(time: 1.007000, values: [1.097561, 1.022472, -0.018741, 0.011978]),
        Pose(time: 1.258750, values: [1.090909, 1.068548, -0.021153, -0.016343]),
        Pose(time: 1.510500, values: [0.977778, 1.092437, 0.009981, -0.029466]),
        Pose(time: 1.762250, values: [0.959732, 1.076596, 0.002833, -0.041425]),
        Pose(time: 2.014000, values: [0.968391, 1.048246, -0.001166, -0.028718]),
        Pose(time: 2.265750, values: [0.994638, 1.040179, -0.010634, -0.000966]),
        Pose(time: 2.517500, values: [1.031830, 1.031532, -0.005842, 0.009482]),
        Pose(time: 2.769250, values: [1.040650, 1.031250, 0.008447, -0.007271]),
        Pose(time: 3.021000, values: [1.043103, 1.035242, 0.014694, -0.015376]),
    ]


    struct Frame {
        let clock: Double
        let deformationClock: Double
        let heart: Double
        let separation: Double
        let radius: CGSize
        let rotationCos: Double
        let rotationSin: Double
        let volume: Double
        let drift: CGPoint
        let screenScale: CGSize

        init(elapsed: Double, flowElapsed: Double? = nil) {
            let poseClock = WelcomeLightMotionClock.time(elapsed) / duration * tau
            clock = WelcomeLightMotionClock.time(flowElapsed ?? elapsed) / duration * tau
            // One monotonically advancing phase closes after exactly one turn.
            // The small periodic speed variation places the circle pose at the
            // reference's 2.52 seconds without a reverse or a stopped endpoint.
            let circlePhase = referenceCircleTime / duration * tau
            let speedWarp = (Double.pi-circlePhase) / (1-cos(circlePhase))
            let phase = poseClock + speedWarp * (1-cos(poseClock))
            let travel = referenceCircleTime * (1-cos(phase)) * 0.5
            let values = pose(at: travel)
            heart = min(max(values[0], 0), 1)
            separation = max(0, values[1])
            radius = CGSize(width: values[2], height: values[3])
            let rotation = phase + 0.12*sin(phase)
            rotationCos = cos(rotation)
            rotationSin = sin(rotation)
            // Keep the accepted circular ribbon pose while letting all waves
            // complete a whole revolution rather than retracing their motion.
            let flowPhase = clock + speedWarp*(1-cos(clock))
            deformationClock = flowPhase + (circlePhase-Double.pi)*0.5*(1-cos(flowPhase))
            volume = values[4]
            let correction = pose(at: travel, using: calibration)
            screenScale = CGSize(width: correction[0], height: correction[1])
            drift = CGPoint(x: values[5] + correction[2], y: values[6] + correction[3])
        }
    }

    /// Natural cubic interpolation preserves the measured poses and makes
    /// acceleration continuous across their joins (the old Hermite was C1).
    private struct PoseCurve {
        let keys: [Pose]
        let curvature: [[Double]]

        init(_ keys: [Pose]) {
            self.keys = keys
            let n = keys.count
            var curvature = keys.map { [Double](repeating: 0, count: $0.values.count) }
            for channel in keys[0].values.indices {
                var diagonal = [Double](repeating: 0, count: n)
                var right = [Double](repeating: 0, count: n)
                var upper = [Double](repeating: 0, count: n)
                diagonal[0] = 1
                diagonal[n-1] = 1
                for index in 1..<n-1 {
                    let left = keys[index].time-keys[index-1].time
                    let next = keys[index+1].time-keys[index].time
                    let rhs = 6*((keys[index+1].values[channel]-keys[index].values[channel])/next
                                 - (keys[index].values[channel]-keys[index-1].values[channel])/left)
                    let factor = left/diagonal[index-1]
                    diagonal[index] = 2*(left+next)-factor*upper[index-1]
                    upper[index] = next
                    right[index] = rhs-factor*right[index-1]
                }
                for index in stride(from: n-2, through: 0, by: -1) {
                    curvature[index][channel] = (right[index]-upper[index]*curvature[index+1][channel])/diagonal[index]
                }
            }
            self.curvature = curvature
        }

        func sample(_ time: Double) -> [Double] {
            let index = min(keys.count-2, keys.lastIndex(where: { $0.time <= time }) ?? 0)
            let start = keys[index], end = keys[index+1]
            let h = end.time-start.time
            let b = (time-start.time)/h, a = 1-b
            return start.values.indices.map { channel in
                a*start.values[channel]+b*end.values[channel]
                    + ((a*a*a-a)*curvature[index][channel]
                       + (b*b*b-b)*curvature[index+1][channel])*h*h/6
            }
        }
    }

    private static let shapeCurve = PoseCurve(poses)
    private static let boundsCurve = PoseCurve(calibration)

    private static func pose(at time: Double, using keys: [Pose]? = nil) -> [Double] {
        (keys == nil ? shapeCurve : boundsCurve).sample(time)
    }

    struct ContourPoint {
        let position: CGPoint
        let normal: CGVector
        let angle: Double
    }

    struct Particle {
        let position: CGPoint
        let opacity: Double
        let diameter: Double
    }

    private struct Cubic {
        let start: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint

        init(_ start: CGPoint, _ control1: CGPoint, _ control2: CGPoint, _ end: CGPoint) {
            self.start = start
            self.control1 = control1
            self.control2 = control2
            self.end = end
        }

        func sample(_ t: Double) -> (CGPoint, CGVector) {
            let u = 1 - t
            let point = CGPoint(
                x: u * u * u * start.x + 3 * u * u * t * control1.x + 3 * u * t * t * control2.x + t * t * t * end.x,
                y: u * u * u * start.y + 3 * u * u * t * control1.y + 3 * u * t * t * control2.y + t * t * t * end.y
            )
            let tangent = CGVector(
                dx: 3 * u * u * (control1.x - start.x) + 6 * u * t * (control2.x - control1.x) + 3 * t * t * (end.x - control2.x),
                dy: 3 * u * u * (control1.y - start.y) + 6 * u * t * (control2.y - control1.y) + 3 * t * t * (end.y - control2.y)
            )
            return (point, tangent)
        }
    }

    // Six independently traced ribbon edges, in the supplied 1036 × 976
    // reference coordinate system. Each pair bounds one cyan/blue/violet sheet.
    // Thirty-two anchors preserve the broad shoulders and the smaller waves along
    // the flanks; the sheets deliberately have different notches and tips.
    static let heartAnchorCount = 32
    private static let referenceRibbonEdges: [[CGPoint]] = [
        [ // Cyan outer
            .init(x: 499, y: 260), .init(x: 446, y: 218),
            .init(x: 375, y: 155), .init(x: 300, y: 134),
            .init(x: 231, y: 145), .init(x: 176, y: 202),
            .init(x: 146, y: 270), .init(x: 103, y: 346),
            .init(x: 132, y: 418), .init(x: 164, y: 475),
            .init(x: 185, y: 539), .init(x: 261, y: 586),
            .init(x: 333, y: 623), .init(x: 389, y: 676),
            .init(x: 467, y: 718), .init(x: 490, y: 784),
            .init(x: 512, y: 824), .init(x: 552, y: 783),
            .init(x: 615, y: 733), .init(x: 677, y: 682),
            .init(x: 723, y: 631), .init(x: 778, y: 584),
            .init(x: 810, y: 520), .init(x: 867, y: 461),
            .init(x: 917, y: 396), .init(x: 915, y: 348),
            .init(x: 869, y: 281), .init(x: 835, y: 218),
            .init(x: 782, y: 168), .init(x: 724, y: 144),
            .init(x: 644, y: 176), .init(x: 558, y: 229)
        ],
        [ // Cyan inner
            .init(x: 518, y: 280), .init(x: 447, y: 234),
            .init(x: 381, y: 188), .init(x: 315, y: 170),
            .init(x: 250, y: 175), .init(x: 196, y: 222),
            .init(x: 167, y: 285), .init(x: 151, y: 354),
            .init(x: 167, y: 416), .init(x: 192, y: 482),
            .init(x: 228, y: 531), .init(x: 284, y: 571),
            .init(x: 353, y: 614), .init(x: 416, y: 663),
            .init(x: 472, y: 739), .init(x: 503, y: 781),
            .init(x: 523, y: 796), .init(x: 572, y: 747),
            .init(x: 628, y: 705), .init(x: 679, y: 666),
            .init(x: 739, y: 625), .init(x: 794, y: 565),
            .init(x: 830, y: 514), .init(x: 863, y: 442),
            .init(x: 888, y: 380), .init(x: 875, y: 325),
            .init(x: 850, y: 267), .init(x: 806, y: 215),
            .init(x: 752, y: 182), .init(x: 702, y: 177),
            .init(x: 633, y: 204), .init(x: 572, y: 251)
        ],
        [ // Blue outer gauze
            .init(x: 522, y: 285), .init(x: 446, y: 203),
            .init(x: 374, y: 127), .init(x: 300, y: 110),
            .init(x: 219, y: 126), .init(x: 161, y: 183),
            .init(x: 113, y: 266), .init(x: 79, y: 338),
            .init(x: 95, y: 420), .init(x: 135, y: 497),
            .init(x: 210, y: 571), .init(x: 264, y: 630),
            .init(x: 350, y: 683), .init(x: 408, y: 738),
            .init(x: 471, y: 775), .init(x: 510, y: 833),
            .init(x: 528, y: 850), .init(x: 581, y: 812),
            .init(x: 638, y: 753), .init(x: 705, y: 712),
            .init(x: 760, y: 648), .init(x: 820, y: 584),
            .init(x: 875, y: 530), .init(x: 916, y: 461),
            .init(x: 946, y: 382), .init(x: 942, y: 318),
            .init(x: 899, y: 247), .init(x: 859, y: 175),
            .init(x: 794, y: 128), .init(x: 730, y: 112),
            .init(x: 653, y: 147), .init(x: 585, y: 209)
        ],
        [ // Blue inner gauze
            .init(x: 504, y: 255), .init(x: 440, y: 208),
            .init(x: 364, y: 159), .init(x: 293, y: 151),
            .init(x: 229, y: 173), .init(x: 177, y: 219),
            .init(x: 147, y: 285), .init(x: 132, y: 350),
            .init(x: 156, y: 418), .init(x: 180, y: 466),
            .init(x: 240, y: 525), .init(x: 293, y: 578),
            .init(x: 349, y: 640), .init(x: 406, y: 696),
            .init(x: 468, y: 724), .init(x: 493, y: 787),
            .init(x: 510, y: 805), .init(x: 562, y: 768),
            .init(x: 622, y: 714), .init(x: 685, y: 670),
            .init(x: 743, y: 620), .init(x: 781, y: 560),
            .init(x: 841, y: 501), .init(x: 878, y: 438),
            .init(x: 909, y: 362), .init(x: 891, y: 313),
            .init(x: 864, y: 256), .init(x: 823, y: 206),
            .init(x: 771, y: 165), .init(x: 714, y: 157),
            .init(x: 635, y: 188), .init(x: 569, y: 237)
        ],
        [ // Violet first fold
            .init(x: 493, y: 275), .init(x: 439, y: 226),
            .init(x: 377, y: 188), .init(x: 312, y: 186),
            .init(x: 253, y: 204), .init(x: 208, y: 252),
            .init(x: 171, y: 310), .init(x: 155, y: 370),
            .init(x: 183, y: 430), .init(x: 228, y: 482),
            .init(x: 252, y: 544), .init(x: 278, y: 579),
            .init(x: 351, y: 613), .init(x: 410, y: 678),
            .init(x: 457, y: 741), .init(x: 474, y: 788),
            .init(x: 497, y: 804), .init(x: 558, y: 786),
            .init(x: 626, y: 739), .init(x: 665, y: 681),
            .init(x: 692, y: 618), .init(x: 746, y: 587),
            .init(x: 802, y: 542), .init(x: 827, y: 474),
            .init(x: 847, y: 404), .init(x: 855, y: 340),
            .init(x: 847, y: 278), .init(x: 812, y: 224),
            .init(x: 763, y: 194), .init(x: 706, y: 184),
            .init(x: 627, y: 215), .init(x: 553, y: 262)
        ],
        [ // Violet crossing fold
            .init(x: 501, y: 247), .init(x: 441, y: 197),
            .init(x: 367, y: 159), .init(x: 296, y: 156),
            .init(x: 230, y: 181), .init(x: 180, y: 231),
            .init(x: 140, y: 298), .init(x: 128, y: 361),
            .init(x: 145, y: 439), .init(x: 170, y: 506),
            .init(x: 240, y: 576), .init(x: 294, y: 620),
            .init(x: 371, y: 662), .init(x: 443, y: 703),
            .init(x: 496, y: 748), .init(x: 520, y: 792),
            .init(x: 538, y: 813), .init(x: 595, y: 762),
            .init(x: 640, y: 701), .init(x: 673, y: 649),
            .init(x: 726, y: 600), .init(x: 784, y: 554),
            .init(x: 838, y: 511), .init(x: 872, y: 453),
            .init(x: 903, y: 386), .init(x: 892, y: 324),
            .init(x: 861, y: 250), .init(x: 829, y: 185),
            .init(x: 771, y: 141), .init(x: 702, y: 134),
            .init(x: 623, y: 174), .init(x: 557, y: 220)
        ]
    ]

    private static func curves(through pixels: [CGPoint]) -> [Cubic] {
        let points = pixels.map {
            CGPoint(x: ($0.x - 528.4) / 412.0, y: ($0.y - 490.8) / 420.1)
        }
        return points.indices.map { index in
            let p0 = points[(index + points.count - 1) % points.count]
            let p1 = points[index]
            let p2 = points[(index + 1) % points.count]
            let p3 = points[(index + 2) % points.count]
            // Centripetal Catmull–Rom keeps unequal anchor spacing from
            // producing tiny loops or cusps at the loosely woven folds.
            let d0 = max(sqrt(hypot(p1.x-p0.x, p1.y-p0.y)), 0.001)
            let d1 = max(sqrt(hypot(p2.x-p1.x, p2.y-p1.y)), 0.001)
            let d2 = max(sqrt(hypot(p3.x-p2.x, p3.y-p2.y)), 0.001)
            let m1 = CGPoint(
                x: ((p1.x-p0.x)/d0 - (p2.x-p0.x)/(d0+d1) + (p2.x-p1.x)/d1)*d1,
                y: ((p1.y-p0.y)/d0 - (p2.y-p0.y)/(d0+d1) + (p2.y-p1.y)/d1)*d1)
            let m2 = CGPoint(
                x: ((p2.x-p1.x)/d1 - (p3.x-p1.x)/(d1+d2) + (p3.x-p2.x)/d2)*d1,
                y: ((p2.y-p1.y)/d1 - (p3.y-p1.y)/(d1+d2) + (p3.y-p2.y)/d2)*d1)
            return Cubic(p1,
                         .init(x: p1.x + m1.x/3, y: p1.y + m1.y/3),
                         .init(x: p2.x - m2.x/3, y: p2.y - m2.y/3), p2)
        }
    }

    // The second overlapping ribbon set crosses the first at these anchored
    // flank folds instead of occupying the same outline. Offsets are anchored
    // distances along the local contour normal, in reference pixels.
    private static let crossingOffsets: [CGFloat] = [
        12, -12, -20, -5, 15, 30, 5, -26,
        -22, 15, 35, 12, -18, -32, -5, 20,
        25, 0, -20, -30, -6, 16, 30, 10,
        -22, -15, 10, 24, -5, -25, -15, 7
    ]
    private static let ribbonCurves: [[Cubic]] = (0..<strandCount * 2).map { strand in
        let ring = strand / strandCount
        let sheet = (strand % strandCount) / 20
        let lane = CGFloat(strand % 20) / 19
        let first = referenceRibbonEdges[sheet*2]
        let second = referenceRibbonEdges[sheet*2+1]
        let points = first.indices.map { index in
            let previous = first[(index + heartAnchorCount - 1) % heartAnchorCount]
            let next = first[(index + 1) % heartAnchorCount]
            let dx = next.x-previous.x, dy = next.y-previous.y
            let length = max(hypot(dx, dy), 1)
            let fold = crossingOffsets[(index + sheet*9) % heartAnchorCount]
            let weave = crossingOffsets[(index + sheet*5 + 4) % heartAnchorCount]
                * sin((lane*2-1)*2.3 + CGFloat(ring)*1.4 + CGFloat(sheet)*1.5) * 0.85
            // Keep the traced lobe crowns round; most of the crossing width
            // belongs on the flanks and at the loose bottom folds.
            let crown = (2...5).contains(index) || (27...30).contains(index)
            let desiredOffset = (fold * (ring == 0 ? 0 : (1-lane)*1.7-0.7) + weave)
                * (crown ? 0.35 : 1)
            let here = first[index]
            let limit = min(hypot(here.x-previous.x, here.y-previous.y),
                            hypot(next.x-here.x, next.y-here.y)) * 0.40
            let offset = limit * tanh(desiredOffset / max(limit, 1))
            return CGPoint(
                x: first[index].x*(1-lane) + second[index].x*lane - dy/length*offset,
                y: first[index].y*(1-lane) + second[index].y*lane + dx/length*offset
            )
        }
        return curves(through: points)
    }
    private static let heartCurves = curves(through: zip(referenceRibbonEdges[0], referenceRibbonEdges[1]).map {
        CGPoint(x: ($0.x + $1.x)/2, y: ($0.y + $1.y)/2)
    })

    static var heartControlPoints: [SIMD2<Float>] {
        ribbonCurves.flatMap { curves in
            curves.flatMap { curve in
                [curve.start, curve.control1, curve.control2, curve.end].map {
                    SIMD2(Float($0.x), Float($0.y))
                }
            }
        }
    }

    private struct Sample {
        let circle: CGPoint
        let circleTangent: CGVector
        let heart: CGPoint
        let heartTangent: CGVector
        let angle: Double
    }

    // Evaluate the two smooth contours once, rather than repeating their math
    // for every filament on every display frame.
    private static let samples: [Sample] = (0..<sampleCount).map { index in
        let angle = Double(index) / Double(sampleCount) * tau
        let section = Double(index) / Double(sampleCount) * Double(heartAnchorCount)
        let segment = Int(section)
        let (heart, tangent) = heartCurves[segment].sample(section - Double(segment))
        return Sample(
            circle: CGPoint(x: -sin(angle), y: -cos(angle)),
            circleTangent: CGVector(dx: -cos(angle) * tau / Double(heartAnchorCount), dy: sin(angle) * tau / Double(heartAnchorCount)),
            heart: heart, heartTangent: tangent, angle: angle
        )
    }

    /// Arc distance from the lower-right flank, continuing around the heart.
    /// One shared lookup keeps the revealing head at an even physical speed.
    private static let heartDistances: [Double] = {
        let points = (0...sampleCount).map { samples[($0 + entranceStartSample) % sampleCount].heart }
        var distance = [Double](repeating: 0, count: sampleCount+1)
        for index in 1...sampleCount {
            distance[index] = distance[index-1] + hypot(points[index].x-points[index-1].x,
                                                        points[index].y-points[index-1].y)
        }
        return distance
    }()
    static var heartPerimeter: Double { heartDistances[sampleCount] }
    static let heartTravel: [Float] = heartDistances.map { Float($0/heartPerimeter) }

    static func contour(ring: Int, frame: Frame) -> [ContourPoint] {
        let side = ring == 0 ? -1.0 : 1.0
        return samples.map { sample in
            let circleX = side * frame.separation + sample.circle.x * frame.radius.width
            let circleY = sample.circle.y * frame.radius.height
            let x = mix(circleX, sample.heart.x, frame.heart)
            let y = mix(circleY, sample.heart.y, frame.heart)
            let dx = mix(sample.circleTangent.dx * frame.radius.width, sample.heartTangent.dx, frame.heart)
            let dy = mix(sample.circleTangent.dy * frame.radius.height, sample.heartTangent.dy, frame.heart)
            let length = max(hypot(dx, dy), 0.0001)
            return ContourPoint(position: CGPoint(x: x, y: y), normal: CGVector(dx: -dy / length, dy: dx / length), angle: sample.angle)
        }
    }

    private static let ribbonSamples: [[CGPoint]] = ribbonCurves.map { curves in
        (0..<sampleCount).map { index in
            let section = Double(index) / Double(sampleCount) * Double(heartAnchorCount)
            return curves[Int(section)].sample(section - floor(section)).0
        }
    }

    static func point(on sample: ContourPoint, ring: Int, filament: Double, frame: Frame, transport: Double = 0, streamStrength: Double = 0) -> CGPoint {
        let side = ring == 0 ? -1.0 : 1.0
        // Three sheets of fine threads, rather than evenly spaced wires on
        // a tube. Neighbouring threads stay close; each sheet drifts differently.
        let sheet = min(Int(filament * 3), 2)
        let lane = (filament * 3 - Double(sheet) - 0.5) * 2
        let phase = Double(sheet) * 2.1 + side * 1.15
        let angle = sample.angle
        let flowSpeed = sheet == 0 ? -2.0 : (sheet == 1 ? 1.0 : -3.0)
        let flow = 2 * angle + flowSpeed * frame.deformationClock + phase
        let swell = 0.035 + 0.065 * frame.heart + 0.020 * pow(sin(frame.deformationClock), 2)
        let billow = swell * (
            0.72 * sin(flow) + 0.30 * sin(angle + frame.deformationClock + phase)
                + 0.22 * sin(3 * angle + 2 * frame.deformationClock + phase)
        )
        let weave = lane * (0.034 + 0.030 * frame.heart) * sin(2 * angle - frame.deformationClock + phase)
        let offset = billow + weave
        let localX = sample.position.x - side * frame.separation

        // Radial expansion lets the silk breathe without folding the rounded
        // heart tip inward or introducing the previous polygon-like ripples.
        let flutter = 0.010 + 0.012 * frame.heart
        let flowingX = sample.position.x + localX * offset + flutter * sin(3 * angle - 2 * frame.deformationClock + phase)
        let flowingY = sample.position.y * (1 + offset) + 0.012 * sin(frame.deformationClock + phase)
            + flutter * 0.65 * cos(2 * angle + 3 * frame.deformationClock + phase)
        let heartFlow = ease(0.15, 0.85, frame.heart)
        let strand = ring * strandCount + min(strandCount-1, max(0, Int(filament*Double(strandCount))))
        let index = min(sampleCount-1, Int((angle/tau)*Double(sampleCount)+0.5))
        let anchor = ribbonSamples[strand][index]
        let carriedWave = sin((angle-entranceStartU*tau)*3-transport*tau*3+phase+lane*0.8)
            * 0.025*streamStrength
        let x = mix(flowingX, anchor.x, heartFlow)+sample.normal.dx*carriedWave
        let y = mix(flowingY, anchor.y, heartFlow)+sample.normal.dy*carriedWave
        let depth = 0.13 * sin(flow + 0.65) + lane * 0.075 * cos(angle - frame.deformationClock + phase)
        let lag = (1-heartFlow) * (0.055 * sin(frame.deformationClock + phase) + lane * 0.018)
        let rotationCos = frame.rotationCos * cos(lag) - frame.rotationSin * sin(lag)
        let rotationSin = frame.rotationSin * cos(lag) + frame.rotationCos * sin(lag)
        let rotatedX = x * rotationCos + depth * rotationSin
        let rotatedZ = -x * rotationSin + depth * rotationCos
        let tilt = (1-heartFlow) * 0.024 * sin(frame.deformationClock + phase)
        let perspective = 1 / (1 + rotatedZ * 0.10 * (1-heartFlow*0.8))
        return CGPoint(
            x: (rotatedX + y * tilt) * perspective,
            y: (y - rotatedX * tilt + rotatedZ * 0.035 * (1-heartFlow)) * perspective
        )
    }

    static func particle(index: Int, elapsed: Double) -> Particle {
        let seed = Double(index)
        // Every component is periodic in the same loop, including its velocity.
        let clock = WelcomeLightMotionClock.time(elapsed) / duration * tau
        let angle = noise(seed + 7) * tau + 0.035 * sin(clock)
        let radius = sqrt(noise(seed + 91)) * 1.10
        let drift = 0.014 * sin(clock + seed)
        let twinkle = pow(0.5 + 0.5 * sin(clock + seed * 2.3), 3)
        return Particle(
            position: CGPoint(x: cos(angle) * (radius + drift), y: sin(angle) * radius),
            opacity: 0.08 + twinkle * 0.48,
            diameter: 0.6 + noise(seed + 43) * 1.2
        )
    }

    private static func ease(_ lower: Double, _ upper: Double, _ value: Double) -> Double {
        let t = min(max((value - lower) / (upper - lower), 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func noise(_ seed: Double) -> Double {
        let value = sin(seed * 127.1 + 311.7) * 43758.5453
        return value - floor(value)
    }
}
