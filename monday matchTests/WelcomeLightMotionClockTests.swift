import XCTest
@testable import monday_match

final class WelcomeLightMotionClockTests: XCTestCase {
    func testCompensatedTimeRemainsForwardAndClosesEveryCycle() {
        let duration = WelcomeLightGeometry.duration
        let dt = duration/720
        for step in -720...1440 {
            let t = Double(step)*dt
            let time = WelcomeLightMotionClock.time(t)
            let next = WelcomeLightMotionClock.time(t+dt)
            XCTAssertGreaterThan(next-time, dt*0.5)
            XCTAssertLessThan(next-time, dt*1.7)
            XCTAssertEqual(WelcomeLightMotionClock.time(t+duration)-time, duration, accuracy: 0.00000001)
        }
    }

    func testCompensationHasMatchingVelocityAndAccelerationAtTheLoopSeam() {
        let epsilon = 0.0001
        for t in [0.0, WelcomeLightGeometry.duration, WelcomeLightGeometry.duration*2] {
            let a = WelcomeLightMotionClock.time(t-2*epsilon)
            let b = WelcomeLightMotionClock.time(t-epsilon)
            let c = WelcomeLightMotionClock.time(t)
            let d = WelcomeLightMotionClock.time(t+epsilon)
            let e = WelcomeLightMotionClock.time(t+2*epsilon)
            XCTAssertEqual((c-b)/epsilon, (d-c)/epsilon, accuracy: 0.001)
            XCTAssertEqual((c-2*b+a)/(epsilon*epsilon), (e-2*d+c)/(epsilon*epsilon), accuracy: 0.02)
        }
    }
}
