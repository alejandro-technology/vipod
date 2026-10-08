import XCTest
@testable import vipod

@MainActor
final class ClassicPlayerMenuTests: XCTestCase {
    func testMainAndMusicMenusExposeStableRowsAndDestinations() async {
        let model = await makeModel(supportsYouTubeDownloads: true)
        #if os(iOS)
        XCTAssertEqual(model.rows.map(\.id), ["menu.music", "menu.nowPlaying", "menu.shuffle", "menu.queue", "menu.settings", "menu.import", "menu.youtubeDownloads"])
        guard let youtubeRow = model.rows.first(where: { $0.id == "menu.youtubeDownloads" }), case .youtubeDownloads = youtubeRow.action else {
            return XCTFail("Expected the YouTube Downloads menu action")
        }
        #else
        XCTAssertEqual(model.rows.map(\.id), ["menu.music", "menu.nowPlaying", "menu.shuffle", "menu.queue", "menu.settings", "menu.import"])
        #endif
        let destinations: [(String, PlayerDestination)] = [
            ("menu.music", .music), ("menu.queue", .queue), ("menu.nowPlaying", .nowPlaying), ("menu.settings", .settings)
        ]
        for (id, destination) in destinations {
            guard let row = model.rows.first(where: { $0.id == id }), case .open(let actual) = row.action else {
                return XCTFail("Expected \(id) to open a destination")
            }
            XCTAssertEqual(actual, destination)
        }

        model.navigation.push(.music)
        XCTAssertEqual(model.rows.map(\.id), ["music.favorites", "music.artists", "music.albums", "music.playlists", "music.songs", "menu.import"])
        for (id, destination) in [("music.artists", PlayerDestination.artists), ("music.albums", .albums), ("music.songs", .songs), ("music.playlists", .playlists), ("music.favorites", .favorites)] {
            guard let row = model.rows.first(where: { $0.id == id }), case .open(let actual) = row.action else {
                return XCTFail("Expected \(id) to open a destination")
            }
            XCTAssertEqual(actual, destination)
        }
    }

    func testAlbumIdentityIncludesArtistAndCollisionProneNamesRemainDistinct() async {
        let tracks = [
            track("One", artist: "A", album: "BC"), track("Two", artist: "AB", album: "C"),
            track("Three", artist: "A", album: "BC"), track("Four", artist: "Different Artist", album: "BC")
        ]
        let model = await makeModel(tracks: tracks)
        model.navigation.push(.albums)
        XCTAssertEqual(model.rows.map(\.title), ["BC", "C", "BC"])
        XCTAssertEqual(Set(model.rows.map(\.id)).count, 3)
        XCTAssertEqual(model.rows.map(\.subtitle), ["A", "AB", "Different Artist"])
        XCTAssertEqual(model.rows.compactMap { row -> PlayerDestination? in
            guard case .open(let destination) = row.action else { return nil }; return destination
        }, [.album(artist: "A", title: "BC"), .album(artist: "AB", title: "C"), .album(artist: "Different Artist", title: "BC")])

        model.navigation.push(.artist(name: "A"))
        XCTAssertEqual(model.rows.map(\.title), ["Albums", "Songs"])
    }

    func testAlbumGroupingUsesAlbumArtistAndCompilationFallbackAndOrdersDiscThenTrack() async throws {
        let tracks = [
            Track(title: "Unknown", artist: "Guest Z", album: "Shared", albumArtist: "Various Artists", audioFilename: "u.mp3"),
            Track(title: "Second", artist: "Guest B", album: "Shared", albumArtist: "Various Artists", trackNumber: 2, discNumber: 1, audioFilename: "2.mp3"),
            Track(title: "Disc Two", artist: "Guest C", album: "Shared", albumArtist: "Various Artists", trackNumber: 1, discNumber: 2, audioFilename: "d2.mp3"),
            Track(title: "First", artist: "Guest A", album: "Shared", albumArtist: "Various Artists", trackNumber: 1, discNumber: 1, audioFilename: "1.mp3"),
            Track(title: "Compilation", artist: "Guest D", album: "Sampler", isCompilation: true, audioFilename: "c.mp3"),
            Track(title: "Compilation two", artist: "Guest E", album: "Sampler", isCompilation: true, audioFilename: "c2.mp3")
        ]
        let model = await makeModel(tracks: tracks)
        model.navigation.push(.albums)
        XCTAssertEqual(model.rows.map(\.title), ["Sampler", "Shared"])
        XCTAssertEqual(model.rows.map(\.subtitle), ["Various Artists", "Various Artists"])
        let sharedAlbum = try XCTUnwrap(model.rows.first { $0.title == "Shared" })
        guard case .open(let destination) = sharedAlbum.action else { return XCTFail("Expected album destination") }
        model.navigation.push(destination)
        XCTAssertEqual(model.rows.map(\.title), ["First", "Second", "Disc Two", "Unknown"])
        guard case .play(_, let queue) = try XCTUnwrap(model.rows.first).action else { return XCTFail("Expected album queue") }
        XCTAssertEqual(queue.map(\.artist), ["Guest A", "Guest B", "Guest C", "Guest Z"])
    }

    func testLegacyTrackCatalogDecodesMissingMetadataWithoutChangingIdentityOrFilenames() throws {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let json = """
        [{"id":"\(id.uuidString)","title":"Song","artist":"Artist","album":"Album","duration":12,"audioFilename":"stable.mp3","artworkFilename":"cover.jpg"}]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([Track].self, from: json)
        XCTAssertEqual(decoded.first?.id, id)
        XCTAssertEqual(decoded.first?.audioFilename, "stable.mp3")
        XCTAssertEqual(decoded.first?.artworkFilename, "cover.jpg")
        XCTAssertNil(decoded.first?.albumArtist)
        XCTAssertNil(decoded.first?.trackNumber)
        XCTAssertNil(decoded.first?.discNumber)
        XCTAssertFalse(decoded.first?.isCompilation ?? true)
    }

    func testFilterRowsAndPlayQueueUseCaseInsensitiveMetadataMatches() async throws {
        let a = track("First", artist: "North", album: "Blue")
        let b = track("Second", artist: "South", album: "Red")
        let c = track("Third", artist: "North", album: "Red")
        let model = await makeModel(tracks: [a, b, c])
        model.navigation.push(.songs)
        for (query, expectedTrack) in [("fIrSt", a), ("sOuTh", b), ("bLuE", a)] {
            model.filterText = query
            XCTAssertEqual(model.rows.map(\.title), [expectedTrack.title])
            guard case .play(let selected, let queue) = try XCTUnwrap(model.rows.first).action else { return XCTFail("Expected play action") }
            XCTAssertEqual(selected, expectedTrack)
            XCTAssertEqual(queue, [expectedTrack])
        }
        model.filterText = "red"
        XCTAssertEqual(model.rows.map(\.title), ["Second", "Third"])
        for row in model.rows {
            guard case .play(_, let queue) = row.action else { return XCTFail("Expected play action") }
            XCTAssertEqual(queue, [b, c])
        }
        model.selectedIndex = 0
        model.selectCurrent()
        XCTAssertEqual(model.playback.currentTrack, b)
        XCTAssertEqual(model.playback.queue.orderedTracks, [b, c])
        model.navigation.pop()
        model.navigation.push(.songs)
        model.filterText = "No match"
        XCTAssertTrue(model.rows.isEmpty)
        model.filterText = ""
        XCTAssertEqual(model.rows.map(\.title), ["First", "Second", "Third"])
    }

    func testSettingsBluetoothRowsFollowConnectedOutput() async throws {
        let suite = "ClassicPlayerMenuTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let route = MenuTestAudioRoute(output: nil)
        let monitor = AudioConnectionMonitor(defaults: defaults, outputProvider: { route.output })
        let model = await makeModel(audioConnection: monitor)
        model.navigation.push(.settings)
        XCTAssertEqual(model.rows.map(\.id), ["theme.black", "theme.white", "settings.shuffle", "repeat.off", "repeat.all", "repeat.one", "menu.import"])

        route.output = BluetoothAudioOutput(uid: "test-output", name: "Test headphones")
        monitor.refresh()
        XCTAssertEqual(model.rows.map(\.id), ["theme.black", "theme.white", "settings.shuffle", "repeat.off", "repeat.all", "repeat.one", "settings.bluetooth.automatic", "settings.bluetooth.airPods", "settings.bluetooth.headphones", "settings.bluetooth.speaker", "menu.import"])
        route.output = nil
        monitor.refresh()
        XCTAssertFalse(model.rows.contains(where: { $0.id.hasPrefix("settings.bluetooth.") }))
    }

    func testArtistAndAlbumBrowsingFiltersRowsAndQueuesWithoutStaleResults() async throws {
        let first = track("One", artist: "Artist", album: "Shared")
        let second = track("Two", artist: "Artist", album: "Shared")
        let otherArtist = track("Three", artist: "Other", album: "Shared")
        let model = await makeModel(tracks: [first, second, otherArtist])
        model.navigation.push(.artist(name: "Artist"))
        XCTAssertEqual(model.rows.map(\.title), ["Albums", "Songs"])
        model.navigation.push(.artistSongs(name: "Artist"))
        XCTAssertEqual(model.rows.map(\.title), ["One", "Two"])
        model.filterText = "one"
        XCTAssertEqual(model.rows.map(\.title), ["One"])
        guard case .play(_, let filteredQueue) = try XCTUnwrap(model.rows.first).action else { return XCTFail("Expected track action") }
        XCTAssertEqual(filteredQueue, [first])
        model.filterText = ""
        model.navigation.pop()
        model.navigation.push(.artistAlbums(name: "Artist"))
        XCTAssertEqual(model.rows.map(\.title), ["Shared"])
        let artistAlbum = try XCTUnwrap(model.rows.first)
        guard case .open(let artistAlbumDestination) = artistAlbum.action else { return XCTFail("Expected artist-scoped album") }
        XCTAssertEqual(artistAlbumDestination, .artistAlbum(artist: "Artist", albumArtist: "Artist", title: "Shared"))
        model.navigation.push(artistAlbumDestination)
        XCTAssertEqual(model.rows.map(\.title), ["One", "Two"])
        model.navigation.returnToRoot()
        model.navigation.push(.album(artist: "Artist", title: "Shared"))
        XCTAssertEqual(model.rows.map(\.title), ["One", "Two"])
        model.filterText = "Other"
        XCTAssertTrue(model.rows.isEmpty)
        model.filterText = "two"
        XCTAssertEqual(model.rows.map(\.title), ["Two"])
        guard case .play(_, let albumQueue) = try XCTUnwrap(model.rows.first).action else { return XCTFail("Expected track action") }
        XCTAssertEqual(albumQueue, [second])
        XCTAssertFalse(albumQueue.contains(otherArtist))
    }

    func testDeviceNameResolverTrimsAndRejectsBlankOrGenericNames() {
        XCTAssertEqual(PlayerDeviceNameResolver.displayName(from: "  Alex’s iPhone  "), "Alex’s iPhone")
        XCTAssertEqual(PlayerDeviceNameResolver.displayName(from: "iPhone de Cristian"), "iPhone de Cristian")
        XCTAssertEqual(PlayerDeviceNameResolver.displayName(from: "iPhone de Alejandro"), "iPhone de Alejandro")
        XCTAssertEqual(PlayerDeviceNameResolver.displayName(from: "iPhone 17 de Cristian"), "iPhone 17 de Cristian")
        XCTAssertEqual(PlayerDeviceNameResolver.displayName(from: "iPhone 17 Work"), "iPhone 17 Work")
        XCTAssertEqual(PlayerDeviceNameResolver.displayName(from: "iPad de Ana"), "iPad de Ana")
        XCTAssertEqual(PlayerDeviceNameResolver.displayName(from: "iPhone"), "iPod")
        XCTAssertEqual(PlayerDeviceNameResolver.displayName(from: "iPad"), "iPod")
        XCTAssertEqual(PlayerDeviceNameResolver.displayName(from: "iPod touch"), "iPod")
        XCTAssertEqual(PlayerDeviceNameResolver.displayName(from: "iPhone 17 Pro"), "iPod")
        XCTAssertEqual(PlayerDeviceNameResolver.displayName(from: "  \n"), "iPod")
        XCTAssertEqual(PlayerDeviceNameResolver.displayName(from: nil), "iPod")
    }

    func testInjectedDeviceNameAppearsInRootAndThemeChoices() async {
        let model = await makeModel(deviceName: "  Alex’s iPhone  ")
        XCTAssertEqual(model.screenTitle, "Alex’s iPhone")
        model.navigation.push(.settings)
        XCTAssertEqual(model.rows.prefix(2).map(\.title), ["Black Alex’s iPhone", "White Alex’s iPhone"])

        let genericModel = await makeModel(deviceName: "iPhone 17")
        XCTAssertEqual(genericModel.screenTitle, "iPod")

        let personalizedModel = await makeModel(deviceName: "iPhone de Cristian")
        XCTAssertEqual(personalizedModel.screenTitle, "iPhone de Cristian")
        personalizedModel.navigation.push(.settings)
        XCTAssertEqual(personalizedModel.rows.prefix(2).map(\.title), ["Black iPhone de Cristian", "White iPhone de Cristian"])
    }

    func testSelectionClampsAndOpeningOrBackingResetsBrowseState() async {
        let model = await makeModel(tracks: [track("One"), track("Two")])
        model.selectedIndex = 100
        XCTAssertEqual(model.selectedRowID, "menu.import")
        model.browse(by: 1)
        XCTAssertEqual(model.selectedIndex, 5)
        model.selectedIndex = -10
        XCTAssertEqual(model.selectedRowID, "menu.music")

        model.filterText = "stale"
        model.isSeeking = true
        model.activate(model.rows[0])
        XCTAssertEqual(model.navigation.currentDestination, .music)
        XCTAssertEqual(model.filterText, "")
        XCTAssertFalse(model.isSeeking)
        model.navigation.push(.songs)
        model.filterText = "none"
        XCTAssertTrue(model.rows.isEmpty)
        model.selectedIndex = 99
        model.normalizeSelection()
        XCTAssertEqual(model.selectedIndex, 0)
        model.menuPressed()
        XCTAssertEqual(model.navigation.currentDestination, .music)
        XCTAssertEqual(model.selectedIndex, 0)
    }

    private func track(_ title: String, artist: String = "Artist", album: String = "Album") -> Track {
        Track(title: title, artist: artist, album: album, audioFilename: "\(title).mp3")
    }

    private func makeModel(tracks: [Track] = [], audioConnection: AudioConnectionMonitor? = nil, deviceName: String = "iPod", supportsYouTubeDownloads: Bool = false) async -> ClassicPlayerModel {
        let library = LibraryController(repository: MenuTestRepository(tracks: tracks))
        await library.load()
        let model = ClassicPlayerModel(library: library, playback: PlaybackController(engine: MenuTestPlayback()), audioConnection: audioConnection, deviceName: deviceName)
        model.supportsYouTubeDownloads = supportsYouTubeDownloads
        return model
    }
}

@MainActor
private final class MenuTestAudioRoute {
    var output: BluetoothAudioOutput?
    init(output: BluetoothAudioOutput?) { self.output = output }
    nonisolated deinit {}
}

private actor MenuTestRepository: TrackRepository {
    let storedTracks: [Track]
    init(tracks: [Track]) { storedTracks = tracks }
    func tracks() async throws -> [Track] { storedTracks }
    func importTracks(from urls: [URL]) async throws -> TrackImportReport { await TrackImportReport(imported: []) }
    func removeTrack(id: UUID) async throws {}
}

@MainActor
private final class MenuTestPlayback: AudioPlayback {
    nonisolated deinit {}
    var status: AudioPlaybackStatus = .idle
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var onEvent: (@MainActor @Sendable (AudioPlaybackEvent) -> Void)?
    var onStateChange: (@MainActor @Sendable () -> Void)?
    func load(_ track: Track) throws { duration = track.duration ?? 0; status = .ready }
    func play() throws { status = .playing }
    func pause() { status = .paused }
    func seek(to seconds: TimeInterval) throws { elapsed = seconds }
    func stop() { status = .idle; elapsed = 0 }
}
