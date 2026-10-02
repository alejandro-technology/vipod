#if os(iOS)
import UIKit
import XCTest

final class PlayerLayoutUITests: XCTestCase {
    func testWheelIsCenteredBelowDisplayAndPhoneStaysPortrait() {
        let app = XCUIApplication()
        app.launch()

        let wheel = app.descendants(matching: .any).matching(identifier: "wheel").firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 10))

        let display = app.descendants(matching: .any).matching(identifier: "classic.display").firstMatch
        XCTAssertTrue(display.exists)
        let wheelFrame = wheel.frame
        let lowerAreaCenterY = (display.frame.maxY + app.frame.maxY) / 2
        XCTAssertEqual(wheelFrame.midY, lowerAreaCenterY, accuracy: 24, "The wheel should be vertically centered between the display and the bottom of the app area, allowing for the iPhone home-indicator inset.")
        XCTAssertEqual(wheelFrame.midX, app.frame.midX, accuracy: 2, "The wheel should be horizontally centered.")
        let previous = app.buttons["wheel.previous"]
        let next = app.buttons["wheel.next"]
        let select = app.buttons["wheel.select"]
        XCTAssertTrue(previous.exists)
        XCTAssertTrue(next.exists)
        XCTAssertTrue(select.exists)
        XCTAssertEqual(previous.frame.midY, wheelFrame.midY, accuracy: 2)
        XCTAssertEqual(next.frame.midY, wheelFrame.midY, accuracy: 2)
        XCTAssertEqual(previous.frame.midX + next.frame.midX, wheelFrame.midX * 2, accuracy: 4, "Previous and Next should be symmetric around the wheel center.")
        XCTAssertEqual(select.frame.midX, wheelFrame.midX, accuracy: 2)
        XCTAssertEqual(select.frame.midY, wheelFrame.midY, accuracy: 2)
        attachScreenshot(of: app, named: "Player - default theme")

        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let originalSize = app.frame.size
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        settleRotationRequest(in: app)
        XCTAssertTrue(waitForSize(app, matching: originalSize), "The iPhone player should remain portrait after a landscape rotation request.")
        XCUIDevice.shared.orientation = .portrait
        settleRotationRequest(in: app)
        XCTAssertTrue(waitForSize(app, matching: originalSize), "The iPhone should return to portrait after the rotation check.")
    }

    func testBlackAndWhiteThemeScreenshots() {
        let app = XCUIApplication()
        app.launch()

        let settings = app.buttons["menu.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        let blackTheme = app.buttons["theme.black"]
        let whiteTheme = app.buttons["theme.white"]
        XCTAssertTrue(blackTheme.waitForExistence(timeout: 5))
        XCTAssertTrue(whiteTheme.waitForExistence(timeout: 5))

        whiteTheme.tap()
        XCTAssertTrue(waitForValue(whiteTheme, equals: "Selected"))
        app.buttons["wheel.menu"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Player root - white theme")

        settings.tap()
        XCTAssertTrue(blackTheme.waitForExistence(timeout: 5))
        blackTheme.tap()
        XCTAssertTrue(waitForValue(blackTheme, equals: "Selected"))
        app.buttons["wheel.menu"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Player root - black theme")
    }

    private func waitForSize(_ app: XCUIApplication, matching size: CGSize) -> Bool {
        let predicate = NSPredicate { _, _ in
            abs(app.frame.width - size.width) < 2 && abs(app.frame.height - size.height) < 2
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func settleRotationRequest(in app: XCUIApplication) {
        // Round-trip through XCTest, then allow UIKit time to apply any accepted rotation.
        _ = app.screenshot()
        let settled = expectation(description: "Rotation request settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
    }

    private func waitForValue(_ element: XCUIElement, equals value: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
