import XCTest
@testable import monday_match

final class WelcomeLightEntranceTests: XCTestCase {
    func testEntranceHandsOverWithMatchingTimeAndVelocity() {
        let end = WelcomeLightEntrance.duration
        let epsilon = 0.0001
        let before = WelcomeLightEntrance.Frame(elapsed: end-epsilon)
        let join = WelcomeLightEntrance.Frame(elapsed: end)
        let after = WelcomeLightEntrance.Frame(elapsed: end+epsilon)
        let incoming = (join.loopElapsed-before.loopElapsed)/epsilon
        let outgoing = (after.loopElapsed-join.loopElapsed)/epsilon
        XCTAssertEqual(incoming, 1, accuracy: 0.00001)
        XCTAssertEqual(outgoing, 1, accuracy: 0.00001)
        XCTAssertEqual(join.inletOpacity, 0)
        XCTAssertEqual(join.headGlow, 0)
        XCTAssertEqual(WelcomeLightEntrance.duration, WelcomeLightEntrance.traceDuration)
        XCTAssertEqual(join.reveal, 1, accuracy: 0.000001)
        XCTAssertEqual(join.streamStrength, 0)
        XCTAssertEqual(join.dustOpacity, 1)

        let start = WelcomeLightEntrance.accelerationStart
        let first = WelcomeLightEntrance.Frame(elapsed: start)
        let next = WelcomeLightEntrance.Frame(elapsed: start+epsilon)
        XCTAssertEqual(first.loopElapsed, 0)
        XCTAssertLessThan(next.loopElapsed/epsilon, 0.00001)
    }

    func testEntranceRunsOnceAndThenKeepsTheExistingLoopClock() {
        XCTAssertLessThan(WelcomeLightEntrance.Frame(elapsed: 0).reveal, 0)
        XCTAssertEqual(WelcomeLightEntrance.Frame(elapsed: WelcomeLightEntrance.traceDuration).reveal, 1, accuracy: 0.000001)
        let start = WelcomeLightEntrance.Frame(elapsed: WelcomeLightEntrance.duration)
        for loop in 1...6 {
            let elapsed = WelcomeLightEntrance.duration + Double(loop)*WelcomeLightGeometry.duration
            let frame = WelcomeLightEntrance.Frame(elapsed: elapsed)
            XCTAssertEqual(frame.loopElapsed-start.loopElapsed, Double(loop)*WelcomeLightGeometry.duration, accuracy: 0.000001)
            XCTAssertGreaterThan(frame.reveal, start.reveal)
            XCTAssertEqual(frame.streamStrength, 0)
            XCTAssertEqual(frame.flowElapsed, frame.loopElapsed, accuracy: 0.000001)
            XCTAssertEqual(frame.inletOpacity, 0)
            XCTAssertEqual(frame.headGlow, 0)
        }
    }

    func testFlyingThreadJoinsTheDiagonalHeartFlankWithTheSameTangent() {
        let frame = WelcomeLightGeometry.Frame(elapsed: 0)
        let point = WelcomeLightGeometry.contour(ring: 0, frame: frame)[WelcomeLightGeometry.entranceStartSample]
        let tangent = CGVector(dx: point.normal.dy, dy: -point.normal.dx)
        XCTAssertGreaterThan(tangent.dx, 0.5)
        XCTAssertLessThan(tangent.dy, -0.4)
        for strand in [0, 19, 20, 39, 40, 59, 60, 79, 80, 99, 100, 119] {
            for transport in [0.0, 0.5, 1.0] {
                let end = WelcomeLightEntrance.inletPoint(1, tip: point.position, tangent: tangent,
                                                          strand: strand, transport: transport)
                let before = WelcomeLightEntrance.inletPoint(0.9999, tip: point.position, tangent: tangent,
                                                             strand: strand, transport: transport)
                XCTAssertEqual(end.x, point.position.x, accuracy: 0.0000001)
                XCTAssertEqual(end.y, point.position.y, accuracy: 0.0000001)
                let dx = end.x-before.x, dy = end.y-before.y
                XCTAssertGreaterThan((dx*tangent.dx+dy*tangent.dy)/hypot(dx,dy), 0.9999)
            }
        }
    }

    func testTheHeadAndMaterialKeepMovingThroughHeartClosure() {
        let end = WelcomeLightEntrance.traceDuration
        let epsilon = 0.0001
        let before = WelcomeLightEntrance.Frame(elapsed: end-epsilon)
        let middle = WelcomeLightEntrance.Frame(elapsed: end)
        let after = WelcomeLightEntrance.Frame(elapsed: end+epsilon)
        let incoming = (middle.reveal-before.reveal)/epsilon
        let outgoing = (after.reveal-middle.reveal)/epsilon
        // Keep a moderate drawing speed while reaching normal loop speed
        // exactly at closure, with no additional settling stage afterwards.
        XCTAssertGreaterThan(1/incoming, WelcomeLightGeometry.duration*0.4)
        XCTAssertLessThan(1/incoming, WelcomeLightGeometry.duration)
        XCTAssertLessThan(middle.headGlow, 0.2)
        XCTAssertEqual(incoming, outgoing, accuracy: 0.00001)
        XCTAssertGreaterThan(after.reveal, 1, "The head must continue around the closed contour.")
        for time in [0.5, 1.0, 1.5, 2.0, 2.5] {
            let a = WelcomeLightEntrance.Frame(elapsed: time)
            let b = WelcomeLightEntrance.Frame(elapsed: time+epsilon)
            XCTAssertEqual((b.flowElapsed-a.flowElapsed)/epsilon, 1, accuracy: 0.00001)
            XCTAssertGreaterThan(a.streamStrength, 0.9)
        }
    }

    func testReducedMotionShowsTheCompleteHeartImmediately() {
        for elapsed in [0.0, 1.5, 12.0] {
            let frame = WelcomeLightEntrance.Frame(elapsed: elapsed, reduceMotion: true)
            XCTAssertEqual(frame.loopElapsed, WelcomeLightGeometry.heartTime)
            XCTAssertEqual(frame.reveal, 2)
            XCTAssertEqual(frame.inletOpacity, 0)
            XCTAssertEqual(frame.headGlow, 0)
            XCTAssertEqual(frame.dustOpacity, 1)
        }
    }
}
