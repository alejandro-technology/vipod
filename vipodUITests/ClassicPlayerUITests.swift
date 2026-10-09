import XCTest

final class ClassicPlayerUITests: XCTestCase {
    func testYouTubePreviewFixtureAnalyzesWithoutDownloadAndInvalidatesOnEdit() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-library-fixture", "--uitesting-reset-library", "--uitesting-youtube-preview"]
        app.launch()

        let entry = app.buttons["menu.youtubeDownloads"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        let url = app.textFields["youtube.download.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText("https://youtu.be/abcdefghijk")
        app.buttons["youtube.download.analyze"].tap()

        XCTAssertTrue(app.staticTexts["youtube.preview.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["youtube.preview.title"].label, "Fixture Track Title")
        XCTAssertTrue(app.staticTexts["Fixture Artist"].exists)
        XCTAssertTrue(app.staticTexts["Source: Fixture Source Channel"].exists)
        XCTAssertTrue(app.buttons["youtube.download.confirm"].exists)
        XCTAssertFalse(app.staticTexts["youtube.download.savedTrack"].exists, "Analysis must not download or import audio.")

        url.tap()
        url.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 128))
        url.typeText("lmnopqrstuv")
        XCTAssertFalse(app.staticTexts["youtube.preview.title"].exists, "Editing the URL must invalidate the previous preview.")
        XCTAssertTrue(app.buttons["youtube.download.analyze"].exists)
    }

    func testYouTubeDownloadsIsAvailableFromNormalMenuAndRetainsValidationOnReopen() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-library-fixture", "--uitesting-reset-library"]
        app.launch()

        let entry = app.buttons["menu.youtubeDownloads"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()

        let urlField = app.textFields["youtube.download.url"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))
        urlField.tap()
        urlField.typeText("invalid")
        app.buttons["youtube.download.analyze"].tap()
        XCTAssertTrue(app.staticTexts["youtube.download.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["youtube.download.error"].label.contains("valid link"))

        app.buttons["youtube.download.done"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.staticTexts["youtube.download.error"].waitForExistence(timeout: 5))
    }

    func testNowPlayingControlsNeighborsAndBothThemes() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-library-fixture", "--uitesting-reset-library"]
        app.launch()

        let settings = app.buttons["menu.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let blackTheme = app.buttons["theme.black"]
        XCTAssertTrue(blackTheme.waitForExistence(timeout: 5))
        blackTheme.tap()
        XCTAssertTrue(waitForValue(blackTheme, equals: "Selected"))
        app.buttons["wheel.menu"].tap()

        let nowPlaying = app.buttons["menu.nowPlaying"]
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 20))
        nowPlaying.tap()

        let currentTitle = app.staticTexts["nowPlaying.title"]
        let display = app.descendants(matching: .any)["classic.display"]
        XCTAssertTrue(display.exists)
        let previous = app.descendants(matching: .any)["nowPlaying.previous"]
        let next = app.descendants(matching: .any)["nowPlaying.next"]
        XCTAssertTrue(currentTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(currentTitle.label, "Alpha")
        XCTAssertEqual(app.sliders.count, 1, "Now Playing should expose exactly one seek control.")
        XCTAssertEqual(app.sliders.firstMatch.label, "Playback position")
        XCTAssertEqual(previous.value as? String, "Unavailable")
        XCTAssertEqual(next.value as? String, "Beta, Fixture")
        assertNeighborsFitAndAlign(previous, next, in: display)
        XCTAssertTrue(app.staticTexts["nowPlaying.elapsed"].exists)
        XCTAssertTrue(app.staticTexts["nowPlaying.duration"].exists)
        XCTAssertTrue(app.staticTexts["nowPlaying.seekHint"].exists)
        XCTAssertTrue(app.staticTexts["Paused"].exists)
        attachNowPlayingScreenshot(from: app, named: "Now Playing — black theme")

        let nextControl = app.buttons["wheel.next"]
        XCTAssertTrue(nextControl.waitForExistence(timeout: 5))
        nextControl.tap()
        XCTAssertEqual(currentTitle.label, "Beta")
        XCTAssertEqual(previous.value as? String, "Alpha, Fixture")
        XCTAssertEqual(next.value as? String, "Gamma, Fixture")
        assertNeighborsFitAndAlign(previous, next, in: display)
        XCTAssertTrue(app.staticTexts["Paused"].exists, "Browsing queue neighbors must not change playback state.")

        app.buttons["wheel.menu"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let whiteTheme = app.buttons["theme.white"]
        XCTAssertTrue(whiteTheme.waitForExistence(timeout: 5))
        whiteTheme.tap()
        XCTAssertTrue(waitForValue(whiteTheme, equals: "Selected"))
        app.buttons["wheel.menu"].tap()
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 5))
        nowPlaying.tap()

        XCTAssertTrue(currentTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(currentTitle.label, "Beta")
        XCTAssertEqual(app.sliders.count, 1)
        XCTAssertEqual(previous.value as? String, "Alpha, Fixture")
        XCTAssertEqual(next.value as? String, "Gamma, Fixture")
        XCTAssertTrue(app.staticTexts["Paused"].exists)
        assertNeighborsFitAndAlign(previous, next, in: display)
        attachNowPlayingScreenshot(from: app, named: "Now Playing — white theme")
    }

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

        app.buttons["track.AAAAAAAA-0000-0000-0000-000000000003"].tap()
        app.buttons["track.action.playNext"].tap()
        app.buttons["track.AAAAAAAA-0000-0000-0000-000000000002"].tap()
        app.buttons["track.action.queueLast"].tap()

        let menu = app.buttons["wheel.menu"]
        menu.tap()
        menu.tap()
        let queue = app.buttons["menu.queue"]
        XCTAssertTrue(queue.waitForExistence(timeout: 5))
        queue.tap()

        XCTAssertTrue(queueTrack("Alpha", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["queue.moveUp"].exists)
        XCTAssertFalse(app.buttons["queue.moveUp"].isEnabled, "The first queue item cannot move up.")
        XCTAssertGreaterThan(app.buttons["queue.moveUp"].frame.minY, app.descendants(matching: .any)["classic.display"].frame.maxY,
                             "Queue operations belong below the LCD.")
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
        XCTAssertTrue(app.buttons["track.AAAAAAAA-0000-0000-0000-000000000003"].exists, "Removing from the queue must leave the library song intact.")
    }

    func testPlaylistAndFavoriteActionsPersistWithoutChangingPlaybackOrLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-library-fixture", "--uitesting-reset-library"]
        app.launch()

        let music = app.buttons["menu.music"]
        XCTAssertTrue(music.waitForExistence(timeout: 20))
        music.tap()
        app.buttons["music.playlists"].tap()
        let display = app.descendants(matching: .any)["classic.display"]
        let createPlaylist = app.buttons["playlist.create"]
        XCTAssertTrue(createPlaylist.isEnabled, "Playlist creation must work while the playlist list is empty.")
        XCTAssertGreaterThan(createPlaylist.frame.minY, display.frame.maxY, "Playlist actions belong below the LCD.")
        app.buttons["playlist.create"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Road Trip")
        app.alerts.buttons["Save"].firstMatch.tap()
        let playlistButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "playlist.open.")).firstMatch
        XCTAssertTrue(playlistButton.waitForExistence(timeout: 5))
        let playlistID = String(playlistButton.identifier.dropFirst("playlist.open.".count))

        app.buttons["playlist.open.\(playlistID)"].tap()
        let rename = app.buttons["playlist.rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()
        let renamedField = app.alerts.textFields.firstMatch
        XCTAssertTrue(renamedField.waitForExistence(timeout: 5))
        renamedField.tap()
        let existingName = renamedField.value as? String ?? ""
        renamedField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingName.count))
        renamedField.typeText("Road Trip Renamed")
        app.alerts.buttons["Save"].firstMatch.tap()
        let renamedPlaylist = app.buttons["playlist.open.\(playlistID)"]
        XCTAssertTrue(renamedPlaylist.waitForExistence(timeout: 5))
        XCTAssertEqual(renamedPlaylist.label, "Road Trip Renamed")

        renamedPlaylist.tap()
        app.buttons["wheel.select"].tap()
        XCTAssertGreaterThan(app.buttons["playlist.addSongs"].frame.minY, display.frame.maxY, "Playlist-member actions belong below the LCD.")
        app.buttons["playlist.addSongs"].tap()
        let alpha = app.buttons["playlist.picker.AAAAAAAA-0000-0000-0000-000000000001"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        alpha.tap()
        app.buttons["wheel.select"].tap()
        let menu = app.buttons["wheel.menu"]
        menu.tap()
        menu.tap()
        menu.tap()
        app.buttons["music.songs"].tap()

        let betaID = "AAAAAAAA-0000-0000-0000-000000000002"
        app.buttons["track.\(betaID)"].tap()
        app.buttons["track.action.playlist"].tap()
        app.buttons["track.addToPlaylist.\(playlistID)"].tap()
        app.buttons["track.action.favorite"].tap()
        app.buttons["track.action.favorite"].tap()
        app.buttons["track.action.favorite"].tap()

        menu.tap()
        app.buttons["music.playlists"].tap()
        app.buttons["playlist.open.\(playlistID)"].tap()
        app.buttons["wheel.select"].tap()
        app.buttons["playlist.member.AAAAAAAA-0000-0000-0000-000000000001"].tap()
        app.buttons["playlist.moveDown"].tap()
        XCTAssertTrue(app.buttons["playlist.member.AAAAAAAA-0000-0000-0000-000000000002"].waitForExistence(timeout: 5))
        XCTAssertEqual(playlistTrackOrder(in: app), ["Beta", "Alpha"])
        app.buttons["playlist.member.AAAAAAAA-0000-0000-0000-000000000001"].tap()
        app.buttons["playlist.remove"].tap()
        XCTAssertEqual(playlistTrackOrder(in: app), ["Beta"])
        XCTAssertTrue(app.staticTexts["Paused"].exists, "Collection edits must not change paused playback.")
        menu.tap()
        menu.tap()
        menu.tap()
        app.buttons["menu.nowPlaying"].tap()
        XCTAssertEqual(app.staticTexts["nowPlaying.title"].label, "Alpha", "Collection edits must leave the paused current track unchanged.")
        XCTAssertTrue(app.staticTexts["Paused"].exists)

        app.terminate()
        app.launchArguments = ["--uitesting-library-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["menu.music"].waitForExistence(timeout: 20))
        app.buttons["menu.music"].tap()
        app.buttons["music.playlists"].tap()
        let restoredPlaylist = app.buttons["playlist.open.\(playlistID)"]
        XCTAssertTrue(restoredPlaylist.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredPlaylist.label, "Road Trip Renamed")
        restoredPlaylist.tap()
        app.buttons["wheel.select"].tap()
        XCTAssertEqual(playlistTrackOrder(in: app), ["Beta"])
        XCTAssertTrue(app.buttons["playlist.member.AAAAAAAA-0000-0000-0000-000000000002"].exists)
        app.buttons["wheel.menu"].tap()
        app.buttons["wheel.menu"].tap()
        app.buttons["music.favorites"].tap()
        XCTAssertTrue(app.buttons["favorites.track.\(betaID)"].waitForExistence(timeout: 5), "The favorite should persist after relaunch.")
        app.buttons["favorites.track.\(betaID)"].tap()
        XCTAssertGreaterThan(app.buttons["favorite.toggle"].frame.minY, app.descendants(matching: .any)["classic.display"].frame.maxY,
                             "Favorite actions belong below the LCD.")
        app.buttons["favorite.toggle"].tap()
        XCTAssertFalse(app.buttons["favorites.track.\(betaID)"].exists, "Unmarking a favorite should remove it from Favorites.")
        app.buttons["wheel.menu"].tap()
        app.buttons["music.songs"].tap()
        for trackID in ["AAAAAAAA-0000-0000-0000-000000000001", "AAAAAAAA-0000-0000-0000-000000000002", "AAAAAAAA-0000-0000-0000-000000000003"] {
            XCTAssertTrue(app.buttons["track.\(trackID)"].exists, "Collection editing must leave every library song intact.")
        }
        app.buttons["wheel.menu"].tap()
        app.buttons["wheel.menu"].tap()
        app.buttons["menu.nowPlaying"].tap()
        XCTAssertEqual(app.staticTexts["nowPlaying.title"].label, "Alpha", "The original paused current track should restore after collection edits.")
        XCTAssertTrue(app.staticTexts["Paused"].exists, "Collection editing must leave playback paused after relaunch.")

        app.buttons["wheel.menu"].tap()
        app.buttons["menu.music"].tap()
        app.buttons["music.playlists"].tap()
        app.buttons["playlist.open.\(playlistID)"].tap()
        let delete = app.buttons["playlist.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertFalse(restoredPlaylist.exists)
        XCTAssertTrue(app.staticTexts["Paused"].exists, "Deleting a playlist must not alter playback.")
    }

    func testSelectingPlaylistMemberStartsThatMemberRatherThanTheFirstTrack() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-library-fixture", "--uitesting-reset-library"]
        app.launch()

        XCTAssertTrue(app.buttons["menu.music"].waitForExistence(timeout: 20))
        app.buttons["menu.music"].tap()
        app.buttons["music.playlists"].tap()
        app.buttons["playlist.create"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Selection Test")
        app.alerts.buttons["Save"].firstMatch.tap()

        let playlist = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "playlist.open.")).firstMatch
        XCTAssertTrue(playlist.waitForExistence(timeout: 5))
        playlist.tap()
        app.buttons["wheel.select"].tap()
        app.buttons["playlist.addSongs"].tap()
        let pickerAlpha = app.buttons["playlist.picker.AAAAAAAA-0000-0000-0000-000000000001"]
        pickerAlpha.tap()
        XCTAssertTrue(app.buttons["playlist.addSelectedSong"].isEnabled)
        app.buttons["playlist.addSelectedSong"].tap()
        let pickerBeta = app.buttons["playlist.picker.AAAAAAAA-0000-0000-0000-000000000002"]
        pickerBeta.tap()
        app.buttons["wheel.select"].tap()
        app.buttons["wheel.menu"].tap()
        let betaMember = app.buttons["playlist.member.AAAAAAAA-0000-0000-0000-000000000002"]
        XCTAssertTrue(betaMember.waitForExistence(timeout: 5))
        let wheel = app.descendants(matching: .any).matching(identifier: "wheel").firstMatch
        XCTAssertTrue(wheel.exists)
        let start = wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.24))
        let end = wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.22))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(betaMember.value as? String, "Selected", "Wheel browsing should highlight the corresponding playlist member.")
        app.buttons["wheel.select"].tap()

        let playingTitle = app.staticTexts["nowPlaying.title"]
        XCTAssertTrue(playingTitle.waitForExistence(timeout: 5), "Selecting Beta from a playlist should return to Now Playing.")
        XCTAssertEqual(playingTitle.label, "Beta", "Selecting Beta from a playlist should make Beta the current track.")

        app.buttons["wheel.playPause"].tap()
        app.buttons["wheel.menu"].tap()
        let alphaMember = app.buttons["playlist.member.AAAAAAAA-0000-0000-0000-000000000001"]
        let betaMemberAfterPause = app.buttons["playlist.member.AAAAAAAA-0000-0000-0000-000000000002"]
        let activeTrackBrowseStart = wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.24))
        let activeTrackBrowseEnd = wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.22))
        activeTrackBrowseStart.press(forDuration: 0.1, thenDragTo: activeTrackBrowseEnd)
        XCTAssertEqual(betaMemberAfterPause.value as? String, "Selected", "Wheel drag should browse the collection while playback is paused.")
        XCTAssertTrue(alphaMember.exists)
        XCTAssertTrue(app.staticTexts["Paused"].exists)
        app.buttons["wheel.menu"].tap()
        app.buttons["wheel.menu"].tap()
        app.buttons["wheel.menu"].tap()
        app.buttons["menu.nowPlaying"].tap()
        XCTAssertEqual(app.staticTexts["nowPlaying.title"].label, "Beta", "Rotary browsing must not change the paused current track.")
    }

    func testLongListsFollowWheelSelectionAndQueueReorder() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-library-fixture", "--uitesting-reset-library", "--uitesting-long-list-fixture"]
        app.launch()

        let queueEntry = app.buttons["menu.queue"]
        XCTAssertTrue(queueEntry.waitForExistence(timeout: 20))
        queueEntry.tap()
        let wheelNext = app.buttons["wheel.next"]
        let selectedQueueTrack = app.buttons["queue.track.BBBBBBBB-0000-0000-0000-000000000013"]
        for _ in 0..<12 { wheelNext.tap() }
        XCTAssertTrue(selectedQueueTrack.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedQueueTrack.value as? String, "Selected")
        XCTAssertTrue(selectedQueueTrack.isHittable, "Wheel browsing should scroll the selected queue row into view.")

        app.buttons["queue.moveUp"].tap()
        XCTAssertEqual(selectedQueueTrack.value as? String, "Selected", "Reordering must retain selection by track UUID.")
        XCTAssertTrue(selectedQueueTrack.isHittable, "The moved selection should remain visible after queue reordering.")

    }

    func testLongPlaylistMembersFollowWheelSelectionAndReorder() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-library-fixture", "--uitesting-reset-library", "--uitesting-long-collection-fixture"]
        app.launch()

        XCTAssertTrue(app.buttons["menu.music"].waitForExistence(timeout: 20))
        app.buttons["menu.music"].tap()
        app.buttons["music.playlists"].tap()
        let playlist = app.buttons["playlist.open.CCCCCCCC-0000-0000-0000-000000000001"]
        XCTAssertTrue(playlist.waitForExistence(timeout: 5))
        playlist.tap()
        app.buttons["wheel.select"].tap()

        let wheelNext = app.buttons["wheel.next"]
        let selectedMember = app.buttons["playlist.member.BBBBBBBB-0000-0000-0000-000000000013"]
        for _ in 0..<12 { wheelNext.tap() }
        XCTAssertTrue(selectedMember.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedMember.value as? String, "Selected")
        XCTAssertTrue(selectedMember.isHittable, "Wheel browsing should scroll the selected playlist member into view.")

        app.buttons["playlist.moveUp"].tap()
        XCTAssertEqual(selectedMember.value as? String, "Selected", "Reordering must retain the selected member UUID.")
        XCTAssertTrue(selectedMember.isHittable, "The moved playlist selection should stay visible.")
    }

    private func playlistTrackOrder(in app: XCUIApplication) -> [String] {
        let titles = [
            "AAAAAAAA-0000-0000-0000-000000000001": "Alpha",
            "AAAAAAAA-0000-0000-0000-000000000002": "Beta",
            "AAAAAAAA-0000-0000-0000-000000000003": "Gamma"
        ]
        return app.buttons.allElementsBoundByIndex.compactMap { button in
            guard button.identifier.hasPrefix("playlist.member."),
                  let title = titles[String(button.identifier.dropFirst("playlist.member.".count))] else { return nil }
            return title
        }
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

    private func attachNowPlayingScreenshot(from app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertNeighborsFitAndAlign(_ previous: XCUIElement, _ next: XCUIElement, in display: XCUIElement) {
        let expectedFooterBottomInset: CGFloat = 6
        XCTAssertTrue(previous.isHittable)
        XCTAssertTrue(next.isHittable)
        XCTAssertGreaterThanOrEqual(previous.frame.minX, display.frame.minX)
        XCTAssertLessThanOrEqual(next.frame.maxX, display.frame.maxX)
        XCTAssertLessThan(previous.frame.minX, next.frame.minX, "Previous should be on the left and Next on the right.")
        XCTAssertGreaterThanOrEqual(previous.frame.minY, display.frame.minY)
        XCTAssertLessThanOrEqual(previous.frame.maxY, display.frame.maxY)
        XCTAssertGreaterThanOrEqual(next.frame.minY, display.frame.minY)
        XCTAssertLessThanOrEqual(next.frame.maxY, display.frame.maxY)
        XCTAssertEqual(previous.frame.maxY, next.frame.maxY, accuracy: 2)
        XCTAssertEqual(previous.frame.maxY, display.frame.maxY - expectedFooterBottomInset, accuracy: 1,
                       "Previous should honor the pinned footer's 6-point bottom inset.")
        XCTAssertEqual(next.frame.maxY, display.frame.maxY - expectedFooterBottomInset, accuracy: 1,
                       "Next should honor the pinned footer's 6-point bottom inset.")
    }
}
