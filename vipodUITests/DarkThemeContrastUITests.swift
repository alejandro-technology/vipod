import XCTest

final class DarkThemeContrastUITests: XCTestCase {
    func testDarkThemeQueueSelectionAndPlaylistModals() throws {
        let app = launchFixture(theme: "black")
        let music = app.buttons["menu.music"]
        XCTAssertTrue(music.waitForExistence(timeout: 20))

        app.buttons["menu.queue"].tap()
        let beta = queueTrack("Beta", in: app)
        XCTAssertTrue(beta.waitForExistence(timeout: 10))
        beta.tap()
        XCTAssertTrue(beta.waitForPredicate("value == 'Selected'", timeout: 5))
        attachScreenshot(app, named: "dark-queue-selected-row")

        let menuButton = app.buttons["wheel.menu"]
        menuButton.tap()
        let musicEntry = app.buttons["menu.music"]
        XCTAssertTrue(musicEntry.waitForExistence(timeout: 10))
        musicEntry.tap()
        let playlists = app.buttons["music.playlists"]
        XCTAssertTrue(playlists.waitForExistence(timeout: 10))
        playlists.tap()

        let create = app.buttons["playlist.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()

        let alertSave = app.buttons["Save"]
        XCTAssertTrue(alertSave.waitForExistence(timeout: 10))
        attachScreenshot(app, named: "dark-modal-new-playlist")

        let nameField = app.textFields.element(boundBy: 0)
        nameField.tap()
        nameField.typeText("Chill Mix")
        alertSave.tap()
        XCTAssertTrue(alertSave.waitForNonExistence(timeout: 10))

        let created = app.buttons.matching(NSPredicate(format: "label == %@", "Chill Mix")).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 10))
        created.tap()

        let rename = app.buttons["playlist.rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 10))
        rename.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "dark-modal-rename-playlist")
        app.buttons["Cancel"].tap()
    }

    func testLightThemeQueueSelectionRegression() throws {
        let app = launchFixture(theme: "white")
        XCTAssertTrue(app.buttons["menu.music"].waitForExistence(timeout: 20))
        app.buttons["menu.queue"].tap()
        let beta = queueTrack("Beta", in: app)
        XCTAssertTrue(beta.waitForExistence(timeout: 10))
        beta.tap()
        XCTAssertTrue(beta.waitForPredicate("value == 'Selected'", timeout: 5))
        attachScreenshot(app, named: "light-queue-selected-row")
    }

    func testDarkThemeYouTubeDownloadsContrast() throws {
        let app = launchFixture(theme: "black", youtubeDownloadFixture: true)
        let entry = app.buttons["menu.youtubeDownloads"]
        XCTAssertTrue(entry.waitForExistence(timeout: 20))
        entry.tap()

        let url = app.textFields["youtube.download.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 10))
        url.tap()
        url.typeText("https://youtu.be/abcdefghijk")
        app.buttons["youtube.download.analyze"].tap()

        let confirm = app.buttons["youtube.download.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        attachScreenshot(app, named: "dark-youtube-preview")

        confirm.tap()
        let progress = app.staticTexts["youtube.download.progress"]
        XCTAssertTrue(progress.waitForPredicate("label == '25%'", timeout: 10))
        attachScreenshot(app, named: "dark-youtube-working")

        app.buttons["youtube.download.cancel"].tap()
        XCTAssertTrue(app.staticTexts["youtube.download.cancelled"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "dark-youtube-cancelled")
    }

    func testDarkThemeSongsFilterAndNowPlaying() throws {
        let app = launchFixture(theme: "black")
        let music = app.buttons["menu.music"]
        XCTAssertTrue(music.waitForExistence(timeout: 20))
        music.tap()
        let songs = app.buttons["music.songs"]
        XCTAssertTrue(songs.waitForExistence(timeout: 10))
        songs.tap()
        XCTAssertTrue(app.buttons["track.AAAAAAAA-0000-0000-0000-000000000001"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "dark-songs-filterbar")

        app.buttons["wheel.menu"].tap()
        app.buttons["wheel.menu"].tap()
        let nowPlaying = app.buttons["menu.nowPlaying"]
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 10))
        nowPlaying.tap()
        XCTAssertTrue(app.staticTexts["nowPlaying.elapsed"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "dark-nowplaying-slider")
    }

    private func launchFixture(theme: String, youtubeDownloadFixture: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = [
            "--uitesting-library-fixture",
            "--uitesting-reset-library",
            "-vipod.theme", theme
        ]
        if youtubeDownloadFixture { arguments.append("--uitesting-youtube-download") }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func queueTrack(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func waitForPredicate(_ format: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
