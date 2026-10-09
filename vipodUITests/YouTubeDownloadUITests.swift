import XCTest

final class YouTubeDownloadUITests: XCTestCase {
    func testFixtureTransferReopensAndSavesOnlyAfterExplicitStageAdvances() throws {
        let app = launchFixture()

        let menu = app.buttons["menu.youtubeDownloads"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        menu.tap()

        let url = app.textFields["youtube.download.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 10))
        url.tap()
        url.typeText("https://youtu.be/abcdefghijk")
        app.buttons["youtube.download.analyze"].tap()

        let preview = app.otherElements["youtube.download.preview"]
        let confirm = app.buttons["youtube.download.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(preview.exists)
        XCTAssertEqual(app.staticTexts["youtube.preview.title"].label, "Fixture Track Title")
        XCTAssertFalse(app.staticTexts["youtube.download.savedTrack"].exists, "Analysis must not save before confirmation.")

        confirm.tap()
        let stage = app.staticTexts["youtube.download.fixtureStage"]
        let progress = app.staticTexts["youtube.download.progress"]
        let advance = app.buttons["youtube.fixture.advance"]
        XCTAssertTrue(stage.waitForExistence(timeout: 10))
        XCTAssertTrue(advance.waitForExistence(timeout: 10))
        XCTAssertEqual(stage.label, "Fixture stage: known-transfer")
        XCTAssertEqual(progress.label, "25%")
        XCTAssertEqual(app.staticTexts["youtube.download.attempt"].label, "Attempt 1")
        XCTAssertEqual(app.progressIndicators.matching(NSPredicate(format: "label == %@", "Audio download progress")).firstMatch.value as? String, "25 percent")
        XCTAssertTrue(app.staticTexts["youtube.download.status"].label.contains("Downloading"))
        XCTAssertFalse(app.staticTexts["youtube.download.savedTrack"].exists)

        app.buttons["youtube.download.done"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        XCTAssertTrue(stage.waitForExistence(timeout: 10))
        XCTAssertEqual(stage.label, "Fixture stage: known-transfer")
        XCTAssertEqual(progress.label, "25%", "Closing the modal must leave the active transfer and its progress intact.")
        XCTAssertEqual(app.staticTexts["youtube.download.attempt"].label, "Attempt 1")

        XCTAssertTrue(advance.waitForExistence(timeout: 5))
        advance.tap()
        XCTAssertTrue(stage.waitForPredicate("label == 'Fixture stage: unknown-transfer'", timeout: 10))
        XCTAssertFalse(progress.exists, "Unknown-length transfer progress is indeterminate after the attempt reset.")
        XCTAssertEqual(app.staticTexts["youtube.download.attempt"].label, "Attempt 2")
        XCTAssertTrue(app.staticTexts["youtube.download.progressIndeterminate"].exists)
        let indeterminateProgress = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Audio download progress")).firstMatch
        XCTAssertTrue(indeterminateProgress.exists, "Unknown-length progress must remain exposed as a labeled accessibility element.")
        XCTAssertEqual(indeterminateProgress.value as? String, "Progress unavailable")
        XCTAssertFalse(app.staticTexts["youtube.download.savedTrack"].exists)

        advance.tap()
        XCTAssertTrue(progress.waitForPredicate("label == '100%'", timeout: 10))
        XCTAssertTrue(stage.waitForPredicate("label == 'Fixture stage: tagging'", timeout: 10))
        XCTAssertEqual(app.progressIndicators.matching(NSPredicate(format: "label == %@", "Audio download progress")).firstMatch.value as? String, "100 percent")
        XCTAssertTrue(app.staticTexts["youtube.download.status"].label.contains("Embedding"))
        XCTAssertFalse(app.staticTexts["youtube.download.savedTrack"].exists, "100% transfer is not the completed save.")

        advance.tap()
        XCTAssertTrue(stage.waitForPredicate("label == 'Fixture stage: importing'", timeout: 10))
        XCTAssertFalse(app.staticTexts["youtube.download.savedTrack"].exists, "Tagging must finish before import/save is allowed.")
        advance.tap()

        let saved = app.staticTexts["youtube.download.savedTrack"]
        XCTAssertTrue(saved.waitForExistence(timeout: 30))
        XCTAssertEqual(saved.label, "Fixture Track Title")
        XCTAssertEqual(url.value as? String, "No URL entered")
        XCTAssertFalse(preview.exists)
        XCTAssertFalse(progress.exists)
        let play = app.buttons["youtube.download.play"]
        XCTAssertTrue(play.exists)
        XCTAssertTrue(app.staticTexts["youtube.download.artworkWarning"].exists)
        play.tap()
        let playbackStatus = app.staticTexts["youtube.download.playbackStatus"]
        XCTAssertTrue(playbackStatus.waitForExistence(timeout: 10))
        XCTAssertTrue(playbackStatus.label.contains("Playback started"))
        attachScreenshot(app, named: "deterministic YouTube saved receipt")

        url.tap()
        url.typeText("https://youtu.be/zzzzzzzzzzz")
        XCTAssertTrue(saved.exists, "Typing the next URL must not discard the independent receipt.")
        app.buttons["youtube.download.analyze"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "The next URL must be analyzable after save.")
        XCTAssertFalse(saved.exists, "Accepting the next analysis starts a new operation and clears the previous receipt.")
    }

    func testCancelRetainsConfirmedPreviewAndRetryCanComplete() throws {
        let app = launchFixture()
        let menu = app.buttons["menu.youtubeDownloads"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        menu.tap()
        let url = app.textFields["youtube.download.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 10))
        url.tap()
        url.typeText("https://youtu.be/abcdefghijk")
        app.buttons["youtube.download.analyze"].tap()

        let confirm = app.buttons["youtube.download.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        let progress = app.staticTexts["youtube.download.progress"]
        XCTAssertTrue(progress.waitForPredicate("label == '25%'", timeout: 10))
        app.buttons["youtube.download.cancel"].tap()
        XCTAssertTrue(app.staticTexts["youtube.download.cancelled"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["youtube.preview.title"].exists)
        XCTAssertEqual(url.value as? String, "https://youtu.be/abcdefghijk")
        XCTAssertEqual(confirm.label, "Retry download")

        confirm.tap()
        XCTAssertTrue(progress.waitForPredicate("label == '25%'", timeout: 10))
        XCTAssertEqual(app.staticTexts["youtube.download.attempt"].label, "Attempt 1", "Retry begins a fresh transfer attempt sequence.")

        let stage = app.staticTexts["youtube.download.fixtureStage"]
        let advance = app.buttons["youtube.fixture.advance"]
        advance.tap()
        XCTAssertTrue(stage.waitForPredicate("label == 'Fixture stage: unknown-transfer'", timeout: 10))
        advance.tap()
        XCTAssertTrue(progress.waitForPredicate("label == '100%'", timeout: 10))
        XCTAssertTrue(stage.waitForPredicate("label == 'Fixture stage: tagging'", timeout: 10))
        advance.tap()
        XCTAssertTrue(stage.waitForPredicate("label == 'Fixture stage: importing'", timeout: 10))
        advance.tap()
        XCTAssertTrue(app.staticTexts["youtube.download.savedTrack"].waitForExistence(timeout: 30))
    }

    func testPreviewRendersInBlackAndWhiteAtLargeDynamicType() throws {
        for theme in ["black", "white"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "--uitesting-library-fixture",
                "--uitesting-reset-library",
                "--uitesting-youtube-preview",
                "-vipod.theme", theme,
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()
            let menu = app.buttons["menu.youtubeDownloads"]
            XCTAssertTrue(menu.waitForExistence(timeout: 20), "Menu should render in \(theme) theme.")
            menu.tap()

            let url = app.textFields["youtube.download.url"]
            XCTAssertTrue(url.waitForExistence(timeout: 10))
            url.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "URL field should expose the keyboard in \(theme) theme.")
            url.typeText("https://youtu.be/abcdefghijk")
            app.buttons["youtube.download.analyze"].tap()

            let title = app.staticTexts["youtube.preview.title"]
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            scrollUntilHittable(title, in: app)
            XCTAssertTrue(title.isHittable, "Large text must remain reachable by scrolling in \(theme) theme.")
            XCTAssertEqual(title.label, "Fixture Track Title")
            let confirm = app.buttons["youtube.download.confirm"]
            scrollUntilHittable(confirm, in: app)
            XCTAssertTrue(confirm.isHittable)
            attachScreenshot(app, named: "YouTube preview — \(theme) — accessibility XXXL")
            app.terminate()
        }
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting-library-fixture",
            "--uitesting-reset-library",
            "--uitesting-youtube-download"
        ]
        app.launch()
        return app
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
    }
}

private extension XCUIElement {
    func waitForPredicate(_ format: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
