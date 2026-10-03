import XCTest

final class ClassicPlayerUITests: XCTestCase {
    func testMenuBackEmptyLibraryImportCTAAndThemeSelection() {
        let app = XCUIApplication()
        app.launch()

        let music = app.buttons["menu.music"]
        XCTAssertTrue(music.waitForExistence(timeout: 10))
        let selectButton = app.buttons["wheel.select"]
        XCTAssertTrue(selectButton.exists)
        selectButton.tap()

        let songs = app.buttons["music.songs"]
        XCTAssertTrue(songs.waitForExistence(timeout: 5))
        songs.tap()
        XCTAssertTrue(app.buttons["library.import"].waitForExistence(timeout: 5))

        let menuButton = app.buttons["wheel.menu"]
        XCTAssertTrue(menuButton.exists)
        menuButton.tap()
        XCTAssertTrue(songs.waitForExistence(timeout: 5), "The first Menu press should return to the Music submenu.")
        menuButton.tap()

        let settings = app.buttons["menu.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let whiteTheme = app.buttons["theme.white"]
        XCTAssertTrue(whiteTheme.waitForExistence(timeout: 5))
        whiteTheme.tap()
        XCTAssertTrue(waitForValue(whiteTheme, equals: "Selected"))

        let blackTheme = app.buttons["theme.black"]
        blackTheme.tap()
        XCTAssertTrue(waitForValue(blackTheme, equals: "Selected"))

        app.buttons["wheel.next"].tap()
        app.buttons["wheel.select"].tap()
        XCTAssertTrue(waitForValue(whiteTheme, equals: "Selected"))
        XCTAssertTrue(waitForExistence(blackTheme, expected: true), "Theme selection should keep the Settings menu visible.")

        app.buttons["wheel.menu"].tap()
        XCTAssertTrue(music.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForExistence(blackTheme, expected: false), "One Menu press should return to the root, without a duplicate Settings destination.")
    }

    func testCircularDragStartingOverMenuMovesTheMenuSelection() {
        let app = XCUIApplication()
        app.launch()

        let menuMusic = app.buttons["menu.music"]
        XCTAssertTrue(menuMusic.waitForExistence(timeout: 10))
        XCTAssertEqual(menuMusic.value as? String, "Selected")

        let wheel = app.descendants(matching: .any).matching(identifier: "wheel").firstMatch
        XCTAssertTrue(wheel.exists)
        let start = wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.24))
        let end = wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.22))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(waitForValue(menuMusic, equals: "Selected", inverted: true), "Dragging from the MENU area should change the selected row.")
        XCTAssertTrue(waitForExistence(app.buttons["menu.settings"], expected: true), "A wheel drag should browse without navigating away from the root menu.")
    }

    func testQueueActionsReorderWithoutPlaybackOrLibraryRemovalAndPersistOnRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-library-fixture", "--uitesting-reset-library"]
        app.launch()

        let music = app.buttons["menu.music"]
        XCTAssertTrue(music.waitForExistence(timeout: 20))
        music.tap()
        app.buttons["music.songs"].tap()

        app.buttons["track.actions.AAAAAAAA-0000-0000-0000-000000000003"].tap()
        app.buttons["track.queueNext.AAAAAAAA-0000-0000-0000-000000000003"].tap()
        app.buttons["track.actions.AAAAAAAA-0000-0000-0000-000000000002"].tap()
        app.buttons["track.queueLast.AAAAAAAA-0000-0000-0000-000000000002"].tap()

        let menu = app.buttons["wheel.menu"]
        menu.tap()
        menu.tap()
        let queue = app.buttons["menu.queue"]
        XCTAssertTrue(queue.waitForExistence(timeout: 5))
        queue.tap()

        XCTAssertTrue(queueTrack("Alpha", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(queueOrder(in: app), ["Alpha", "Gamma", "Beta"])
        XCTAssertEqual(queueTrack("Alpha", in: app).value as? String, "Now Playing")
        XCTAssertEqual(app.staticTexts["Paused"].exists, true)

        queueTrack("Beta", in: app).tap()
        app.buttons["queue.moveUp"].tap()
        XCTAssertEqual(queueOrder(in: app), ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(queueTrack("Beta", in: app).value as? String, "Selected", "The selected queue track should stay selected when its row moves.")
        queueTrack("Gamma", in: app).tap()
        app.buttons["queue.remove"].tap()
        XCTAssertEqual(queueOrder(in: app), ["Alpha", "Beta"])
        XCTAssertEqual(queueTrack("Alpha", in: app).value as? String, "Now Playing")
        XCTAssertEqual(app.staticTexts["Paused"].exists, true, "Queue edits must not restart the paused current track.")

        app.terminate()
        app.launchArguments = ["--uitesting-library-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["menu.queue"].waitForExistence(timeout: 20))
        app.buttons["menu.queue"].tap()
        XCTAssertEqual(queueOrder(in: app), ["Alpha", "Beta"], "The edited queue should restore after relaunch.")
        XCTAssertTrue(queueTrack("Alpha", in: app).exists)
        XCTAssertEqual(queueTrack("Alpha", in: app).value as? String, "Now Playing")
        XCTAssertTrue(app.staticTexts["Paused"].exists)

        app.buttons["wheel.menu"].tap()
        app.buttons["menu.music"].tap()
        app.buttons["music.songs"].tap()
        XCTAssertTrue(app.buttons["track.actions.AAAAAAAA-0000-0000-0000-000000000003"].exists, "Removing from the queue must leave the library song intact.")
    }

    private func queueOrder(in app: XCUIApplication) -> [String] {
        app.buttons.allElementsBoundByIndex.compactMap { button in
            let title = button.label.components(separatedBy: ",").first ?? button.label
            return ["Alpha", "Beta", "Gamma"].contains(title) ? title : nil
        }
    }

    private func queueTrack(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func waitForValue(_ element: XCUIElement, equals value: String, inverted: Bool = false) -> Bool {
        let predicate = NSPredicate(format: inverted ? "value != %@" : "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        return result == .completed
    }

    private func waitForExistence(_ element: XCUIElement, expected: Bool) -> Bool {
        let predicate = NSPredicate(format: "exists == %@", NSNumber(value: expected))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
