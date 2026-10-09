import XCTest

final class YouTubeRuntimeUITests: XCTestCase {
    func testDeterministicPreviewShowsEffectiveMetadataBeforeDownload() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-library-fixture", "--uitesting-reset-library", "--uitesting-youtube-preview"]
        app.launch()

        let menuEntry = app.buttons["menu.youtubeDownloads"]
        XCTAssertTrue(menuEntry.waitForExistence(timeout: 20))
        menuEntry.tap()
        let url = app.textFields["youtube.download.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 10))
        url.tap()
        url.typeText("https://youtu.be/abcdefghijk")
        app.buttons["youtube.download.analyze"].tap()

        XCTAssertTrue(app.buttons["youtube.download.confirm"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["youtube.preview.title"].label, "Fixture Track Title")
        XCTAssertTrue(app.staticTexts["Fixture Artist"].exists)
        XCTAssertTrue(app.staticTexts["Source: Fixture Source Channel"].exists)
        XCTAssertTrue(app.staticTexts["Release date"].exists)
        XCTAssertFalse(app.staticTexts["youtube.download.savedTrack"].exists)
    }

    func testRequestedVideoThroughProductionMenu() throws {
        guard ProcessInfo.processInfo.environment["VIPOD_RUN_YOUTUBE_RUNTIME_TESTS"] == "1" else {
            throw XCTSkip("Set VIPOD_RUN_YOUTUBE_RUNTIME_TESTS=1 to opt into live YouTube runtime tests.")
        }

        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-library-fixture", "--uitesting-reset-library"]
        app.launch()

        let menuEntry = app.buttons["menu.youtubeDownloads"]
        XCTAssertTrue(menuEntry.waitForExistence(timeout: 20))
        menuEntry.tap()
        let savedTrack = app.staticTexts["youtube.download.savedTrack"]
        let failure = app.staticTexts["youtube.download.error"]
        let playbackStatus = app.staticTexts["youtube.download.playbackStatus"]
        let url = app.textFields["youtube.download.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 10))
        analyzeAndConfirm(url: url, app: app)
        attachPhase("first-download-started", app: app)

        XCTAssertTrue(waitForDownloadTerminal(app: app, savedTrack: savedTrack, failure: failure), "First production download did not reach a terminal UI state.")
        attachPhase("first-download-terminal", app: app)

        if savedTrack.exists {
            XCTAssertFalse(savedTrack.label.isEmpty)
            let titleReceipt = XCTAttachment(string: "Imported track title: \(savedTrack.label)")
            titleReceipt.name = "Requested YouTube video import receipt"
            titleReceipt.lifetime = .keepAlways
            add(titleReceipt)
            app.buttons["youtube.download.play"].tap()
            XCTAssertTrue(playbackStatus.waitForExistence(timeout: 10))
            XCTAssertTrue(playbackStatus.label.contains("Playback started"))

            analyzeAndConfirm(url: url, app: app)
            attachPhase("second-download-submitted", app: app)

            let oldPlaybackStatusCleared = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: playbackStatus)
            wait(for: [oldPlaybackStatusCleared], timeout: 10)
            XCTAssertFalse(playbackStatus.exists, "Second submission did not clear the first operation's playback receipt.")

            guard waitForDownloadTerminal(app: app, savedTrack: savedTrack, failure: failure) else {
                attachPhase("second-download-terminal-timeout", app: app)
                XCTFail("Second production download remained in state: \(downloadState(status: app.staticTexts["youtube.download.status"], savedTrack: savedTrack, failure: failure, playbackStatus: playbackStatus))")
                return
            }
            attachPhase("second-download-terminal", app: app)

            if savedTrack.exists {
                XCTAssertFalse(savedTrack.label.isEmpty)
                let secondTitle = XCTAttachment(string: "Second completed import title: \(savedTrack.label)")
                secondTitle.name = "Second same-process completed import"
                secondTitle.lifetime = .keepAlways
                add(secondTitle)
                app.buttons["youtube.download.play"].tap()
                XCTAssertTrue(playbackStatus.waitForExistence(timeout: 10))
                XCTAssertTrue(playbackStatus.label.contains("Playback started"), "Second completed import did not play: \(playbackStatus.label)")
                attachPhase("second-import-playback-started", app: app)
            } else if failure.exists {
                let errorMessage = failure.label
                let typedDuplicate = errorMessage.localizedCaseInsensitiveContains("already in your music library")
                let secondError = XCTAttachment(string: "Second same-process operation failed: \(errorMessage)")
                secondError.name = typedDuplicate ? "Second transfer typed duplicate" : "Second transfer error"
                secondError.lifetime = .keepAlways
                add(secondError)
                XCTAssertTrue(typedDuplicate, "Second production download failed: \(errorMessage)")
            } else {
                attachPhase("second-download-unclassified-terminal", app: app)
                XCTFail("Second production operation reached an unrecognized terminal UI state.")
            }
        } else {
            attachPhase("first-download-failed", app: app)
            XCTFail("Production download failed: \(failure.label)")
        }
    }

    private func analyzeAndConfirm(url: XCUIElement, app: XCUIApplication) {
        url.tap()
        url.typeText("https://youtu.be/gtqEDfuGK_k")
        app.buttons["youtube.download.analyze"].tap()
        let confirm = app.buttons["youtube.download.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 120), "Analysis should produce a reviewable preview before a download is allowed.")
        XCTAssertTrue(app.staticTexts["youtube.preview.title"].exists)
        confirm.tap()
    }

    private func waitForDownloadTerminal(app: XCUIApplication, savedTrack: XCUIElement, failure: XCUIElement) -> Bool {
        let status = app.staticTexts["youtube.download.status"]
        guard status.waitForExistence(timeout: 20) else { return false }
        let finished = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: status)
        wait(for: [finished], timeout: 660)
        return savedTrack.exists || failure.exists
    }

    private func attachPhase(_ phase: String, app: XCUIApplication) {
        let status = app.staticTexts["youtube.download.status"]
        let savedTrack = app.staticTexts["youtube.download.savedTrack"]
        let failure = app.staticTexts["youtube.download.error"]
        let playbackStatus = app.staticTexts["youtube.download.playbackStatus"]
        let attachment = XCTAttachment(string: """
        Phase: \(phase)
        Download status: \(status.exists ? status.label : "<not displayed>")
        Saved track: \(savedTrack.exists ? savedTrack.label : "<not displayed>")
        Error: \(failure.exists ? failure.label : "<not displayed>")
        Playback status: \(playbackStatus.exists ? playbackStatus.label : "<not displayed>")
        Accessibility hierarchy:
        \(app.debugDescription)
        """)
        attachment.name = "YouTube production phase — \(phase)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func downloadState(status: XCUIElement, savedTrack: XCUIElement, failure: XCUIElement, playbackStatus: XCUIElement) -> String {
        let statusText = status.exists ? status.label : "<not displayed>"
        let savedText = savedTrack.exists ? savedTrack.label : "<not displayed>"
        let errorText = failure.exists ? failure.label : "<not displayed>"
        let playbackText = playbackStatus.exists ? playbackStatus.label : "<not displayed>"
        return "status=\(statusText), saved=\(savedText), error=\(errorText), playback=\(playbackText)"
    }

    func testExplicitLiveYouTubeRuntimeImport() throws {
        guard ProcessInfo.processInfo.environment["VIPOD_RUN_YOUTUBE_RUNTIME_TESTS"] == "1" else {
            throw XCTSkip("Set VIPOD_RUN_YOUTUBE_RUNTIME_TESTS=1 to opt into the live YouTube runtime diagnostic.")
        }

        let app = XCUIApplication()
        let usesIsolatedFixture = ProcessInfo.processInfo.environment["VIPOD_YOUTUBE_REAL_LIBRARY"] != "1"
        app.launchArguments = usesIsolatedFixture
            ? ["--uitesting-library-fixture", "--uitesting-reset-library"]
            : []
        app.launchArguments += [
            "--youtube-poc",
            "--youtube-poc-autorun",
            "--youtube-url=https://www.youtube.com/watch?v=jNQXAC9IVRw"
        ]
        app.launch()

        let status = app.staticTexts["youtube.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 15), "The explicit Debug diagnostic must be visible.")
        let terminalDiagnostic = NSPredicate(
            format: "label CONTAINS 'Imported' OR label CONTAINS 'Python ' OR label CONTAINS 'No direct HTTPS' OR label CONTAINS 'network'"
        )
        expectation(for: terminalDiagnostic, evaluatedWith: status)
        waitForExpectations(timeout: 125)
        XCTAssertTrue(status.label.contains("playback started"), "Extraction, import, or AVFoundation playback failed: \(status.label)")
        XCTAssertTrue(status.label.contains("Apple WebKit solved 1/1 N/Sig challenges"), "This video did not demonstrate an Apple WebKit N/Sig challenge solution: \(status.label)")

        app.buttons["youtube.run"].tap()
        let secondAcceptedOperation = NSPredicate(
            format: "label CONTAINS 'Imported' OR label CONTAINS 'already in your library'"
        )
        expectation(for: secondAcceptedOperation, evaluatedWith: status)
        waitForExpectations(timeout: 125)
        XCTAssertTrue(
            status.label.contains("Imported") || status.label.contains("already in your library"),
            "A second accepted extraction must finish as a new import or a repository-owned duplicate: \(status.label)"
        )

        app.terminate()
        app.launchArguments = usesIsolatedFixture
            ? ["--uitesting-library-fixture", "--youtube-poc"]
            : ["--youtube-poc"]
        app.launch()
        let savedTrack = app.staticTexts["youtube.savedTrack"]
        XCTAssertTrue(savedTrack.waitForExistence(timeout: 20), "The downloaded track must remain in the app-owned library after relaunch.")
        XCTAssertTrue(savedTrack.label.contains("Me at the zoo"))
        app.buttons["youtube.playSavedLocal"].tap()
        XCTAssertTrue(app.staticTexts["youtube.status"].label.contains("Saved local audio playback started"))
    }
}
