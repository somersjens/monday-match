import XCTest
@testable import Stop_Swiping

@MainActor
final class WelcomeLightGeometryTests: XCTestCase {
    func testBackgroundParticlesDoNotResetAtShapeLoopBoundary() {
        let epsilon = 0.0001
        for loop in 1...8 {
            let boundary = Double(loop) * WelcomeLightGeometry.duration
            for index in 0..<160 {
                let before = WelcomeLightGeometry.particle(index: index, elapsed: boundary - epsilon)
                let after = WelcomeLightGeometry.particle(index: index, elapsed: boundary + epsilon)
                XCTAssertLessThan(distance(before.position, after.position), 0.0001)
                XCTAssertLessThan(abs(before.opacity - after.opacity), 0.0002)
                let middle = WelcomeLightGeometry.particle(index: index, elapsed: boundary)
                let incoming = (middle.opacity-before.opacity)/epsilon
                let outgoing = (after.opacity-middle.opacity)/epsilon
                XCTAssertEqual(incoming, outgoing, accuracy: 0.001)
            }
        }
    }

    func testFilamentsMatchInPositionAndVelocityAcrossTheLoop() {
        let duration = WelcomeLightGeometry.duration
        let epsilon = 0.0001
        for ring in 0..<2 {
            for filament in [0.0, 0.17, 0.5, 0.83] {
                let initial = positions(elapsed: 0, ring: ring, filament: filament)
                let end = positions(elapsed: duration, ring: ring, filament: filament)
                let before = positions(elapsed: duration - epsilon, ring: ring, filament: filament)
                let after = positions(elapsed: duration + epsilon, ring: ring, filament: filament)
                for index in initial.indices {
                    XCTAssertLessThan(distance(initial[index], end[index]), 0.0000001)
                    let incoming = CGPoint(x: (end[index].x - before[index].x) / epsilon, y: (end[index].y - before[index].y) / epsilon)
                    let outgoing = CGPoint(x: (after[index].x - end[index].x) / epsilon, y: (after[index].y - end[index].y) / epsilon)
                    XCTAssertLessThan(distance(incoming, outgoing), 0.003)
                }
            }
        }
    }

    func testRoundRingsJoinBeforeTheHeartForms() {
        let start = WelcomeLightGeometry.Frame(elapsed: WelcomeLightGeometry.circleTime)
        for ring in 0..<2 {
            let centerX = ring == 0 ? -0.48 : 0.48
            for sample in WelcomeLightGeometry.contour(ring: ring, frame: start) {
                let x = (sample.position.x - centerX) / start.radius.width
                let y = sample.position.y / start.radius.height
                XCTAssertEqual(x * x + y * y, 1, accuracy: 0.000001)
            }
        }

        let overlap = WelcomeLightGeometry.Frame(elapsed: 3.8)
        XCTAssertLessThan(overlap.separation, start.separation * 0.8)
        XCTAssertLessThan(overlap.heart, 0.15)

        let heart = WelcomeLightGeometry.Frame(elapsed: WelcomeLightGeometry.heartTime)
        XCTAssertEqual(heart.separation, 0, accuracy: 0.000001)
        XCTAssertEqual(heart.heart, 1, accuracy: 0.000001)
        let contour = WelcomeLightGeometry.contour(ring: 0, frame: heart)
        XCTAssertGreaterThan(contour[0].position.y - contour[contour.count / 8].position.y, 0.20)
    }

    func testContourTangentsRemainRoundedThroughoutTheMorph() {
        // A polygon-like corner produces a sudden normal change between samples.
        for step in 0...60 {
            let frame = WelcomeLightGeometry.Frame(elapsed: Double(step) / 60 * WelcomeLightGeometry.duration)
            for ring in 0..<2 {
                let contour = WelcomeLightGeometry.contour(ring: ring, frame: frame)
                for index in contour.indices {
                    let a = contour[index].normal
                    let b = contour[(index + 1) % contour.count].normal
                    XCTAssertGreaterThan(a.dx * b.dx + a.dy * b.dy, 0.85)
                }
            }
        }
    }

    func testVisibleFilamentsHaveNoSharpCornersAtCircleOrHeart() {
        for elapsed in [WelcomeLightGeometry.circleTime, WelcomeLightGeometry.heartTime] {
            for ring in 0..<2 {
                for strand in 0..<WelcomeLightGeometry.strandCount {
                    let points = positions(elapsed: elapsed, ring: ring, filament: Double(strand) / Double(WelcomeLightGeometry.strandCount))
                    for index in points.indices {
                        let previous = points[(index + points.count - 1) % points.count]
                        let current = points[index]
                        let next = points[(index + 1) % points.count]
                        let ax = current.x - previous.x
                        let ay = current.y - previous.y
                        let bx = next.x - current.x
                        let by = next.y - current.y
                        let dot = (ax * bx + ay * by) / (hypot(ax, ay) * hypot(bx, by))
                        XCTAssertGreaterThan(dot, 0.88)
                    }
                }
            }
        }
    }

    private func positions(elapsed: Double, ring: Int, filament: Double) -> [CGPoint] {
        let frame = WelcomeLightGeometry.Frame(elapsed: elapsed)
        return WelcomeLightGeometry.contour(ring: ring, frame: frame).map {
            WelcomeLightGeometry.point(on: $0, ring: ring, filament: filament, frame: frame)
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }
}
