import XCTest
@testable import vipod

@MainActor
final class LibraryCollectionControllerTests: XCTestCase {
    func testCreateRenameAndDeletePlaylistPublishesExpectedCatalog() async throws {
        let store = CollectionMemoryStore()
        let controller = LibraryCollectionController(store: store)
        let createdID = await controller.createPlaylist(named: " Road Trip ")
        let playlistID = try XCTUnwrap(createdID)
        XCTAssertEqual(controller.catalog.playlists, [LibraryPlaylist(id: playlistID, name: "Road Trip")])

        await controller.renamePlaylist(id: playlistID, to: "Evening")
        XCTAssertEqual(controller.catalog.playlists.first?.name, "Evening")
        await controller.deletePlaylist(id: playlistID)
        XCTAssertTrue(controller.catalog.playlists.isEmpty)
    }

    func testPlaylistMutationsPreserveStableIDsAndOtherPlaylists() async throws {
        let a = makeTrack("A"); let b = makeTrack("B"); let c = makeTrack("C")
        let first = LibraryPlaylist(name: "First", trackIDs: [a.id, b.id, c.id])
        let other = LibraryPlaylist(name: "Other", trackIDs: [b.id])
        let controller = LibraryCollectionController(store: CollectionMemoryStore(), tracks: [a, b, c], catalog: .init(playlists: [first, other]))

        await controller.addTrack(b.id, toPlaylist: first.id)
        await controller.removeTrack(b.id, fromPlaylist: first.id)
        await controller.reorderPlaylist(first.id, trackIDs: [c.id, a.id])

        XCTAssertEqual(controller.catalog.playlists.first(where: { $0.id == first.id })?.trackIDs, [c.id, a.id])
        XCTAssertEqual(controller.catalog.playlists.first(where: { $0.id == other.id })?.trackIDs, [b.id])
    }

    func testFavoritesPersistAcrossFreshControllerAndLibraryDeletionReconcilesWithoutDeletingAudio() async throws {
        let track = makeTrack("Favorite")
        let store = CollectionMemoryStore()
        let first = LibraryCollectionController(store: store, tracks: [track])
        await first.setFavorite(track.id, isFavorite: true)
        let reloaded = LibraryCollectionController(store: store, tracks: [track])
        await reloaded.load()
        XCTAssertTrue(reloaded.catalog.favoriteTrackIDs.contains(track.id))

        await reloaded.updateLibraryTracks([])
        XCTAssertFalse(reloaded.catalog.favoriteTrackIDs.contains(track.id))
        let saved = try await store.load()
        XCTAssertTrue(saved.favoriteTrackIDs.isEmpty)
    }

    func testMusicMenuExposesStablePlaylistAndFavoriteEntries() {
        let rows = ClassicPlayerMenuBuilder().rows(for: .music, tracks: [], filterText: "", hasConnectedAudioOutput: false)
        XCTAssertTrue(rows.contains { $0.id == "music.playlists" })
        XCTAssertTrue(rows.contains { $0.id == "music.favorites" })
    }

    func testBlankNamesAreRejectedAndSaveFailureDoesNotPublish() async {
        let store = CollectionMemoryStore(failsSaves: true)
        let controller = LibraryCollectionController(store: store)
        let blankID = await controller.createPlaylist(named: " \n ")
        XCTAssertNil(blankID)
        let id = await controller.createPlaylist(named: "Road Trip")
        XCTAssertNil(id)
        XCTAssertTrue(controller.catalog.playlists.isEmpty)
        XCTAssertNotNil(controller.errorMessage)
    }

    func testPresentationSelectionTracksPlaylistReorderAndChoosesNeighborAfterRemoval() async throws {
        let tracks = [makeTrack("A"), makeTrack("B"), makeTrack("C")]
        let library = LibraryController(repository: CollectionTestRepository(tracks: tracks))
        await library.load()
        let collections = LibraryCollectionController(store: CollectionMemoryStore(), tracks: tracks)
        await collections.load()
        let createdPlaylistID = await collections.createPlaylist(named: "Selection")
        let playlistID = try XCTUnwrap(createdPlaylistID)
        for track in tracks { await collections.addTrack(track.id, toPlaylist: playlistID) }

        let model = ClassicPlayerModel(library: library, playback: PlaybackController(engine: CollectionTestPlayback()), collections: collections)
        model.navigation.push(.playlist(id: playlistID))
        model.selectRow(model.rows[1])
        await model.movePlaylistTrack(playlistID: playlistID, trackID: tracks[1].id, by: 1)
        XCTAssertEqual(model.selectedSongTrack?.id, tracks[1].id, "Reordering must preserve the selected track identity.")

        await model.removeFromPlaylist(tracks[1].id, playlistID: playlistID)
        XCTAssertEqual(model.selectedSongTrack?.id, tracks[2].id, "Removing the selected member should select the adjacent surviving row.")
    }

    func testPlaylistListingSelectionSurvivesRenameAndMovesToNeighborAfterDeletion() async throws {
        let library = LibraryController(repository: CollectionTestRepository(tracks: []))
        await library.load()
        let collections = LibraryCollectionController(store: CollectionMemoryStore())
        await collections.load()
        let createdFirst = await collections.createPlaylist(named: "First")
        let createdSecond = await collections.createPlaylist(named: "Second")
        let first = try XCTUnwrap(createdFirst)
        let second = try XCTUnwrap(createdSecond)
        let model = ClassicPlayerModel(library: library, playback: PlaybackController(engine: CollectionTestPlayback()), collections: collections)
        model.navigation.push(.playlists)
        model.selectRow(try XCTUnwrap(model.rows.first))

        await model.renamePlaylist(id: first, to: "Renamed")
        XCTAssertEqual(model.selectedRowID, "playlist.\(first.uuidString)", "Rename must preserve the selected playlist identity.")
        await model.deletePlaylist(id: first)
        XCTAssertEqual(model.selectedRowID, "playlist.\(second.uuidString)", "Deleting the selected playlist should select the neighboring playlist.")
    }

    func testOpeningPlaylistSongPickerResetsSelectionForItsFilteredRows() async throws {
        let tracks = [makeTrack("A"), makeTrack("B"), makeTrack("C"), makeTrack("D")]
        let library = LibraryController(repository: CollectionTestRepository(tracks: tracks))
        await library.load()
        let playlist = LibraryPlaylist(name: "Picker", trackIDs: [tracks[0].id, tracks[2].id])
        let collections = LibraryCollectionController(store: CollectionMemoryStore(), tracks: tracks, catalog: .init(playlists: [playlist]))
        let model = ClassicPlayerModel(library: library, playback: PlaybackController(engine: CollectionTestPlayback()), collections: collections)
        model.navigation.push(.playlist(id: playlist.id))
        model.selectRow(model.rows[1])

        model.openPlaylistSongPicker(for: playlist.id)

        XCTAssertEqual(model.navigation.currentDestination, .playlistSongPicker(id: playlist.id))
        XCTAssertEqual(model.rows.map(\.title), ["B", "D"])
        XCTAssertEqual(model.selectedRow?.title, "B", "Picker selection should start at its first available row, not a stale member index.")
    }

    func testFileStoreRoundTripsAndMissingFileLoadsEmptyCatalog() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileLibraryCollectionStore(storageURL: root)
        let missing = try await store.load()
        XCTAssertEqual(missing, LibraryCollectionCatalog())
        let playlist = LibraryPlaylist(name: "Saved", trackIDs: [UUID()])
        let catalog = LibraryCollectionCatalog(playlists: [playlist], favoriteTrackIDs: [UUID()])
        try await store.save(catalog)
        let saved = try await store.load()
        XCTAssertEqual(saved, catalog)
    }

    func testFileStoreReportsCorruptCatalogAndWriteFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: root.appendingPathComponent("library-collections.json"))
        let store = FileLibraryCollectionStore(storageURL: root)
        do { _ = try await store.load(); XCTFail("Corrupt data must be visible") }
        catch { }

        let blockedRoot = root.appendingPathComponent("blocked")
        try Data().write(to: blockedRoot)
        do { try await FileLibraryCollectionStore(storageURL: blockedRoot).save(.init()); XCTFail("Write error must be visible") }
        catch { }
    }

    func testMutationBeforeExplicitLoadPreservesExistingPlaylists() async throws {
        let store = CollectionMemoryStore()
        let existing = LibraryPlaylist(name: "Existing")
        try await store.save(.init(playlists: [existing]))
        let controller = LibraryCollectionController(store: store)

        let id = await controller.createPlaylist(named: "New")

        XCTAssertNotNil(id)
        XCTAssertEqual(controller.catalog.playlists.map(\.name), ["Existing", "New"])
        XCTAssertEqual(controller.catalog.playlists.first?.id, existing.id)
    }

    func testCorruptCatalogBlocksWritesAndPreservesOriginalBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("library-collections.json")
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: file)
        let track = makeTrack("A")
        let controller = LibraryCollectionController(store: FileLibraryCollectionStore(storageURL: root), tracks: [track])
        await controller.load()
        XCTAssertNotNil(controller.errorMessage)

        let id = await controller.createPlaylist(named: "Must Not Overwrite")
        await controller.setFavorite(track.id, isFavorite: true)
        await controller.updateLibraryTracks([])

        XCTAssertNil(id)
        XCTAssertTrue(controller.catalog.playlists.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
        XCTAssertNotNil(controller.errorMessage)
    }

    func testConcurrentCreationAndPruningSerializeWithoutLostUpdates() async throws {
        let a = makeTrack("A")
        let b = makeTrack("B")
        let playlist = LibraryPlaylist(name: "Original", trackIDs: [a.id, b.id])
        let store = DelayedCollectionStore(catalog: .init(playlists: [playlist], favoriteTrackIDs: [a.id, b.id]))
        let controller = LibraryCollectionController(store: store, tracks: [a, b])
        await controller.load()
        await store.delayNextSave()
        let create = Task { await controller.createPlaylist(named: "New") }
        await store.waitForSave()
        let prune = Task { await controller.updateLibraryTracks([b]) }
        await Task.yield()
        await store.releaseSave()
        let createdID = await create.value
        await prune.value

        XCTAssertNotNil(createdID)
        XCTAssertEqual(controller.catalog.playlists.map(\.name), ["Original", "New"])
        XCTAssertEqual(controller.catalog.playlists.first?.trackIDs, [b.id])
        XCTAssertEqual(controller.catalog.favoriteTrackIDs, [b.id])
        let fresh = LibraryCollectionController(store: store, tracks: [b])
        await fresh.load()
        XCTAssertEqual(fresh.catalog, controller.catalog)
    }

    func testQueuedFavoriteTogglesUseLatestCommittedState() async {
        let track = makeTrack("A")
        let store = DelayedCollectionStore(catalog: .init())
        let collections = LibraryCollectionController(store: store, tracks: [track])
        await collections.load()
        let model = ClassicPlayerModel(library: LibraryController(repository: CollectionTestRepository(tracks: [track])),
                                      playback: PlaybackController(engine: CollectionTestPlayback()), collections: collections)
        await store.delayNextSave()
        let first = Task { await model.toggleFavorite(track.id) }
        await store.waitForSave()
        var second: Task<Void, Never>?
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            second = Task {
                started.resume()
                await model.toggleFavorite(track.id)
            }
        }
        await store.releaseSave()
        await first.value
        await second?.value
        XCTAssertFalse(collections.catalog.favoriteTrackIDs.contains(track.id), "Two toggles must cancel even when the first save is suspended.")
    }

    func testCollectionFailureIsPresentedWithoutChangingPlaybackOrDeletingAudio() async {
        let track = makeTrack("A")
        let store = CollectionMemoryStore(failsSaves: true)
        let collections = LibraryCollectionController(store: store, tracks: [track])
        let repository = CollectionTestRepository(tracks: [track])
        let playback = PlaybackController(engine: CollectionTestPlayback(), tracks: [track])
        playback.play(track)
        playback.seek(to: 17)
        playback.pause()
        let model = ClassicPlayerModel(library: LibraryController(repository: repository), playback: playback, collections: collections)

        await model.toggleFavorite(track.id)

        XCTAssertNotNil(model.presentationError)
        XCTAssertEqual(playback.currentTrack?.id, track.id)
        XCTAssertEqual(playback.elapsed, 17)
        XCTAssertEqual(playback.status, .paused)
        let removals = await repository.removeCount()
        XCTAssertEqual(removals, 0)
    }

    func testQueuedPlaylistMovesUseLatestCommittedOrder() async {
        let tracks = [makeTrack("A"), makeTrack("B"), makeTrack("C")]
        let playlist = LibraryPlaylist(name: "Ordered", trackIDs: tracks.map(\.id))
        let store = DelayedCollectionStore(catalog: .init(playlists: [playlist]))
        let collections = LibraryCollectionController(store: store, tracks: tracks)
        await collections.load()
        let model = ClassicPlayerModel(library: LibraryController(repository: CollectionTestRepository(tracks: tracks)),
                                      playback: PlaybackController(engine: CollectionTestPlayback()), collections: collections)
        await store.delayNextSave()
        let first = Task { await model.movePlaylistTrack(playlistID: playlist.id, trackID: tracks[0].id, by: 1) }
        await store.waitForSave()
        var second: Task<Void, Never>?
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            second = Task {
                started.resume()
                await model.movePlaylistTrack(playlistID: playlist.id, trackID: tracks[0].id, by: 1)
            }
        }
        await store.releaseSave()
        await first.value
        await second?.value
        XCTAssertEqual(collections.catalog.playlists.first?.trackIDs, [tracks[1].id, tracks[2].id, tracks[0].id])
    }

    func testPlaylistSelectionStartsSelectedMemberWithSavedPlaybackOrder() async {
        let tracks = [makeTrack("A"), makeTrack("B"), makeTrack("C")]
        let playlist = LibraryPlaylist(name: "Ordered", trackIDs: [tracks[2].id, tracks[0].id, tracks[1].id])
        let collections = LibraryCollectionController(store: DelayedCollectionStore(catalog: .init(playlists: [playlist])), tracks: tracks)
        await collections.load()
        let library = LibraryController(repository: CollectionTestRepository(tracks: tracks))
        await library.load()
        let playback = PlaybackController(engine: CollectionTestPlayback(), tracks: tracks, randomIndex: { _ in 0 })
        playback.toggleShuffle()
        let model = ClassicPlayerModel(library: library, playback: playback, collections: collections)
        model.navigation.push(.playlist(id: playlist.id))

        model.activate(model.rows[2])

        XCTAssertEqual(playback.currentTrack?.id, tracks[1].id)
        XCTAssertEqual(playback.queue.orderedTracks.map(\.id), playlist.trackIDs, "Starting a saved playlist should not inherit an unrelated queue's shuffle order.")
        XCTAssertEqual(playback.status, .playing)
    }

    private func makeTrack(_ title: String) -> Track {
        Track(title: title, artist: "Artist", album: "Album", audioFilename: "\(title).mp3")
    }
}

private actor DelayedCollectionStore: LibraryCollectionStore {
    private var catalog: LibraryCollectionCatalog
    private var shouldDelay = false
    private var saveGate: CheckedContinuation<Void, Never>?
    private var saveStarted: CheckedContinuation<Void, Never>?
    init(catalog: LibraryCollectionCatalog) { self.catalog = catalog }
    func load() async throws -> LibraryCollectionCatalog { catalog }
    func save(_ catalog: LibraryCollectionCatalog) async throws {
        if shouldDelay {
            shouldDelay = false
            await withCheckedContinuation { continuation in
                saveGate = continuation
                saveStarted?.resume()
                saveStarted = nil
            }
        }
        self.catalog = catalog
    }
    func delayNextSave() { shouldDelay = true }
    func waitForSave() async {
        if saveGate == nil { await withCheckedContinuation { saveStarted = $0 } }
    }
    func releaseSave() { saveGate?.resume(); saveGate = nil }
}

private actor CollectionMemoryStore: LibraryCollectionStore {
    private var value = LibraryCollectionCatalog()
    private var saves = 0
    private let failsSaves: Bool
    init(failsSaves: Bool = false) { self.failsSaves = failsSaves }
    func load() async throws -> LibraryCollectionCatalog { value }
    func save(_ catalog: LibraryCollectionCatalog) async throws {
        if failsSaves { throw NSError(domain: "CollectionMemoryStore", code: 1) }
        value = catalog
        saves += 1
    }
    func saveCount() -> Int { saves }
}

private actor CollectionTestRepository: TrackRepository {
    let storedTracks: [Track]
    private var removals = 0
    init(tracks: [Track]) { storedTracks = tracks }
    func tracks() async throws -> [Track] { storedTracks }
    func importTracks(from urls: [URL]) async throws -> TrackImportReport { await .init(imported: []) }
    func removeTrack(id: UUID) async throws { removals += 1 }
    func removeCount() -> Int { removals }
}

@MainActor
private final class CollectionTestPlayback: AudioPlayback {
    nonisolated deinit {}
    var status: AudioPlaybackStatus = .idle
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 60
    var onEvent: (@MainActor @Sendable (AudioPlaybackEvent) -> Void)?
    var onStateChange: (@MainActor @Sendable () -> Void)?
    func load(_ track: Track) throws { status = .ready }
    func play() throws { status = .playing }
    func pause() { status = .paused }
    func seek(to seconds: TimeInterval) throws { elapsed = seconds }
    func stop() { status = .idle; elapsed = 0 }
}
