import XCTest

final class YouTubeRuntimeUITests: XCTestCase {
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
        let duplicateReport = NSPredicate(format: "label CONTAINS 'already in your library'")
        expectation(for: duplicateReport, evaluatedWith: status)
        waitForExpectations(timeout: 125)
        XCTAssertTrue(status.label.contains("already in your library"), "A second extraction must finish and report the repository-owned duplicate: \(status.label)")

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
