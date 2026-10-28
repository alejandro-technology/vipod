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
        let previewCard = app.otherElements["youtube.download.preview"]
        let transferCard = app.otherElements["youtube.download.workStatus"]
        let musicBrainzHeading = app.staticTexts["youtube.musicbrainz.heading"]
        XCTAssertTrue(previewCard.exists)
        XCTAssertTrue(transferCard.exists)
        XCTAssertTrue(musicBrainzHeading.exists)
        XCTAssertLessThan(previewCard.frame.maxY, transferCard.frame.minY)
        XCTAssertLessThan(transferCard.frame.maxY, musicBrainzHeading.frame.minY)

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

    func testMusicBrainzSearchAppliesSelectedTrackAndSavesItWithoutLiveNetwork() throws {
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
        XCTAssertTrue(app.textFields["youtube.metadata.title"].exists)
        let search = app.buttons["youtube.musicbrainz.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable, "The MusicBrainz search action should be visible and directly tappable.")
        search.tap()

        let recording = app.buttons["youtube.musicbrainz.recording.0"]
        XCTAssertTrue(recording.waitForExistence(timeout: 10))
        XCTAssertTrue(recording.label.contains("Electronic"))
        XCTAssertTrue(recording.label.contains("First released 2001-02-03"))
        XCTAssertTrue(recording.label.contains("1 album edition"))
        scrollUntilHittable(recording, in: app)
        recording.tap()

        let stepTitle = app.staticTexts["youtube.musicbrainz.stepTitle"]
        let back = app.buttons["youtube.musicbrainz.back"]
        XCTAssertEqual(stepTitle.label, "Choose an album")
        XCTAssertEqual(back.label, "Back to recordings")
        let release = app.buttons["youtube.musicbrainz.release.0"]
        XCTAssertTrue(release.waitForExistence(timeout: 10))
        XCTAssertTrue(release.label.contains("2001-02-03"))
        XCTAssertTrue(release.label.contains("1 track"))
        scrollUntilHittable(release, in: app)
        release.tap()

        let track = app.buttons["youtube.musicbrainz.track.0"]
        XCTAssertTrue(track.waitForExistence(timeout: 10))
        XCTAssertEqual(stepTitle.label, "Choose a track")
        XCTAssertEqual(back.label, "Back to albums")
        XCTAssertTrue(track.label.contains("MusicBrainz Fixture Artist"))
        XCTAssertTrue(track.label.contains("Track 1 of 1"))
        XCTAssertTrue(track.label.contains("Disc 1 of 1"))

        back.tap()
        XCTAssertTrue(release.waitForExistence(timeout: 5), "Back should return to the album list.")
        XCTAssertFalse(track.exists, "Only the active step's list should be displayed.")
        back.tap()
        XCTAssertTrue(recording.waitForExistence(timeout: 5), "Back should return to the recording list.")
        XCTAssertFalse(release.exists, "Album choices should be hidden while choosing a recording.")
        recording.tap()
        release.tap()
        XCTAssertTrue(track.waitForExistence(timeout: 10))
        XCTAssertFalse(track.isSelected)
        XCTAssertEqual(track.value as? String, "Not selected")
        track.tap()
        XCTAssertTrue(track.waitForPredicate("selected == true", timeout: 5))
        XCTAssertEqual(track.value as? String, "Selected")

        XCTAssertEqual(app.textFields["youtube.metadata.title"].value as? String, "MusicBrainz Fixture Track")
        XCTAssertEqual(app.textFields["youtube.metadata.artist"].value as? String, "MusicBrainz Fixture Artist")
        XCTAssertEqual(app.textFields["youtube.metadata.album"].value as? String, "MusicBrainz Fixture Album")
        XCTAssertEqual(app.staticTexts["youtube.preview.title"].label, "MusicBrainz Fixture Track")

        for _ in 0..<6 where !confirm.isHittable { app.swipeDown() }
        confirm.tap()
        let advance = app.buttons["youtube.fixture.advance"]
        XCTAssertTrue(advance.waitForExistence(timeout: 10))
        let stage = app.staticTexts["youtube.download.fixtureStage"]
        advance.tap()
        XCTAssertTrue(stage.waitForPredicate("label == 'Fixture stage: unknown-transfer'", timeout: 10))
        advance.tap()
        XCTAssertTrue(stage.waitForPredicate("label == 'Fixture stage: tagging'", timeout: 10))
        advance.tap()
        XCTAssertTrue(stage.waitForPredicate("label == 'Fixture stage: importing'", timeout: 10))
        advance.tap()

        let saved = app.staticTexts["youtube.download.savedTrack"]
        XCTAssertTrue(saved.waitForExistence(timeout: 30))
        XCTAssertEqual(saved.label, "MusicBrainz Fixture Track")
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
