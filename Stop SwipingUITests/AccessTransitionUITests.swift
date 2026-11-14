import XCTest

final class AccessTransitionUITests: XCTestCase {
    @MainActor
    func testLifetimeIsDefaultAndLightReturnsByTapAndSwipe() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 20))
        getStarted.tap()

        let lifetime = app.buttons["access.lifetime"]
        let early = app.buttons["access.earlyAdopter"]
        XCTAssertTrue(lifetime.waitForExistence(timeout: 10))
        XCTAssertTrue(early.exists)
        XCTAssertTrue(lifetime.isSelected)
        XCTAssertFalse(early.isSelected)
        XCTAssertLessThan(lifetime.frame.minY, early.frame.minY)
        XCTAssertFalse(app.buttons["access.reminder"].exists)
        XCTAssertFalse(app.buttons["access.close"].exists)

        let light = app.descendants(matching: .any)["access.back"].firstMatch
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Lifetime default below continuous welcome light"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(light.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(light.isHittable)
        XCTAssertLessThan(light.frame.minY, 120)

        light.tap()
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.tap()
        XCTAssertTrue(light.waitForExistence(timeout: 5))
        light.swipeDown()
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
    }
}
