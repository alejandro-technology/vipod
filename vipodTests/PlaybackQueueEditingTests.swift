import XCTest
@testable import vipod

@MainActor
final class PlaybackQueueEditingTests: XCTestCase {
    func testNeighborPreviewsFollowManualBoundariesAndRepeatAll() throws {
        let a = track("A"), b = track("B"), c = track("C")
        let emptyQueue = PlaybackQueue()
        XCTAssertNil(emptyQueue.previousTrack)
        XCTAssertNil(emptyQueue.nextTrack)
        var queue = PlaybackQueue(tracks: [a, b, c])
        XCTAssertNil(queue.previousTrack)
        XCTAssertNil(queue.nextTrack)

        _ = queue.select(id: a.id)
        XCTAssertNil(queue.previousTrack)
        XCTAssertEqual(queue.nextTrack?.id, b.id)
        _ = queue.select(id: b.id)
        XCTAssertEqual(queue.previousTrack?.id, a.id)
        XCTAssertEqual(queue.nextTrack?.id, c.id)
        _ = queue.select(id: c.id)
        XCTAssertEqual(queue.previousTrack?.id, b.id)
        XCTAssertNil(queue.nextTrack)

        queue.setRepeatMode(.all)
        XCTAssertEqual(queue.nextTrack?.id, a.id)
        _ = queue.select(id: a.id)
        XCTAssertEqual(queue.previousTrack?.id, c.id)
        XCTAssertEqual(queue.nextTrack?.id, b.id)
    }

    func testRepeatOneDoesNotPreviewCurrentAndSingletonWrapsOnlyForRepeatAll() {
        let solo = track("Solo")
        var queue = PlaybackQueue(tracks: [solo])
        _ = queue.select(id: solo.id)
        queue.setRepeatMode(.one)
        XCTAssertNil(queue.previousTrack)
        XCTAssertNil(queue.nextTrack)
        queue.setRepeatMode(.all)
        XCTAssertEqual(queue.previousTrack?.id, solo.id)
        XCTAssertEqual(queue.nextTrack?.id, solo.id)
    }

    func testPreviewsUseShuffleOrderAndDoNotMutateQueue() throws {
        let tracks = [track("A"), track("B"), track("C")]
        var queue = PlaybackQueue(tracks: tracks)
        queue.restore(tracks: tracks, selectedID: tracks[1].id, repeatMode: .off, isShuffled: true,
                      shuffledIDs: [tracks[2].id, tracks[1].id, tracks[0].id])
        let beforeOrder = queue.orderedTracks.map(\.id)
        let beforeIndex = queue.currentIndex
        XCTAssertEqual(queue.previousTrack?.id, tracks[2].id)
        XCTAssertEqual(queue.nextTrack?.id, tracks[0].id)
        XCTAssertEqual(queue.orderedTracks.map(\.id), beforeOrder)
        XCTAssertEqual(queue.currentIndex, beforeIndex)
        XCTAssertEqual(queue.currentTrack?.id, tracks[1].id)
    }

    func testPreviewsFollowQueueReorderAndRemovalAndRequireCurrentSelection() {
        let a = track("A"), b = track("B"), c = track("C")
        var queue = PlaybackQueue(tracks: [a, b, c])
        _ = queue.select(id: b.id)
        queue.move(id: c.id, toVisibleIndex: 0)
        XCTAssertEqual(queue.previousTrack?.id, a.id)
        XCTAssertNil(queue.nextTrack)
        queue.remove(id: b.id)
        XCTAssertNil(queue.previousTrack)
        XCTAssertNil(queue.nextTrack)
        XCTAssertNil(queue.currentTrack)
    }

    func testPlayNextAndAddLastRepositionUniqueTracksWithoutReloadingCurrentPlayback() throws {
        let a = track("A"), b = track("B"), c = track("C")
        let engine = QueueEditingTestEngine()
        let playback = PlaybackController(engine: engine, tracks: [a, b, c])
        playback.play(b)
        try engine.seek(to: 37)
        let loadCount = engine.loadCount
        let initialStatus = playback.status

        playback.playNext(c)
        XCTAssertEqual(playback.queue.orderedTracks.map(\.id), [a.id, b.id, c.id])
        XCTAssertEqual(playback.currentTrack?.id, b.id)
        XCTAssertEqual(playback.elapsed, 37)
        XCTAssertEqual(playback.status, initialStatus)
        XCTAssertEqual(engine.loadCount, loadCount)

        playback.addLast(a)
        XCTAssertEqual(playback.queue.orderedTracks.map(\.id), [b.id, c.id, a.id])
        playback.playNext(b)
        XCTAssertEqual(playback.queue.orderedTracks.map(\.id), [b.id, c.id, a.id])
    }

    func testExplicitMovePreservesCurrentTrackAndInvalidBoundariesAreNoOps() {
        let a = track("A"), b = track("B"), c = track("C")
        let engine = QueueEditingTestEngine()
        let playback = PlaybackController(engine: engine, tracks: [a, b, c])
        playback.play(b)
        let loads = engine.loadCount

        playback.moveQueueItem(id: a.id, to: 2)
        XCTAssertEqual(playback.queue.orderedTracks.map(\.id), [b.id, c.id, a.id])
        XCTAssertEqual(playback.currentTrack?.id, b.id)
        XCTAssertEqual(engine.loadCount, loads)
        playback.moveQueueItem(id: a.id, to: -1)
        playback.moveQueueItem(id: a.id, to: 99)
        XCTAssertEqual(playback.queue.orderedTracks.map(\.id), [b.id, c.id, a.id])
    }

    func testRemovingBackgroundTrackKeepsCurrentAndRemovingCurrentStopsWithoutReplacement() {
        let a = track("A"), b = track("B"), c = track("C")
        let engine = QueueEditingTestEngine()
        let playback = PlaybackController(engine: engine, tracks: [a, b, c])
        playback.play(b)
        playback.removeTrack(id: a.id)
        XCTAssertEqual(playback.currentTrack?.id, b.id)
        XCTAssertEqual(engine.status, .playing)
        playback.removeTrack(id: b.id)
        XCTAssertNil(playback.currentTrack)
        XCTAssertEqual(playback.queue.orderedTracks.map(\.id), [c.id])
        XCTAssertEqual(engine.status, .idle)
        XCTAssertEqual(engine.loadCount, 1)
    }

    func testMainMenuContainsStableQueueEntry() async {
        let model = await makeModel()
        XCTAssertTrue(model.rows.contains { $0.id == "menu.queue" })
    }

    func testShuffleEditsUseVisibleOrderAndKeepCurrentItemInPlace() {
        let tracks = [track("A"), track("B"), track("C"), track("D")]
        let engine = QueueEditingTestEngine()
        let playback = PlaybackController(engine: engine, tracks: tracks, randomIndex: { _ in 0 })
        playback.toggleShuffle()
        let visible = playback.queue.orderedTracks
        let current = try! XCTUnwrap(visible.first)
        let added = tracks.first { $0.id != current.id }!
        playback.play(current)
        playback.playNext(added)

        let order = playback.queue.orderedTracks.map(\.id)
        let currentIndex = try! XCTUnwrap(order.firstIndex(of: current.id))
        XCTAssertEqual(order[currentIndex + 1], added.id)
        XCTAssertEqual(playback.currentTrack?.id, current.id)
        XCTAssertTrue(playback.isShuffled)
    }

    func testEmptyQueueEditsDoNotAutoplayAndAddingCurrentTrackIsNoOp() {
        let engine = QueueEditingTestEngine()
        let playback = PlaybackController(engine: engine)
        let track = track("Solo")
        playback.addLast(track)
        XCTAssertEqual(playback.queue.orderedTracks.map(\.id), [track.id])
        XCTAssertEqual(engine.loadCount, 0)
        XCTAssertEqual(engine.status, .idle)

        playback.play(track)
        let snapshot = playback.queue.orderedTracks.map(\.id)
        playback.playNext(track)
        playback.addLast(track)
        XCTAssertEqual(playback.queue.orderedTracks.map(\.id), snapshot)
        XCTAssertEqual(engine.loadCount, 1)
    }

    func testQueueEditsArePersistedByExistingSessionController() async throws {
        let a = track("A"), b = track("B"), c = track("C")
        let store = QueueEditingTestSessionStore()
        let playback = PlaybackController(engine: QueueEditingTestEngine(), tracks: [a, b, c], sessionStore: store)
        await playback.restoreSession(after: [a, b, c])
        playback.moveQueueItem(id: a.id, to: 2)
        await playback.flushSession()
        let persisted = await store.savedSession()
        let saved = try XCTUnwrap(persisted)
        XCTAssertEqual(saved.queueIDs, [b.id, c.id, a.id])
    }

    func testRemovingFromPlaybackQueueDoesNotRemoveLibraryTrack() async {
        let track = track("Library Song")
        let repository = QueueEditingTestRepository(tracks: [track])
        let library = LibraryController(repository: repository)
        await library.load()
        let playback = PlaybackController(engine: QueueEditingTestEngine(), tracks: [track])
        let model = ClassicPlayerModel(library: library, playback: playback)
        model.removeQueueTrack(id: track.id)

        XCTAssertTrue(playback.queue.orderedTracks.isEmpty)
        XCTAssertEqual(library.tracks.map(\.id), [track.id])
        let removalCount = await repository.removalCount
        XCTAssertEqual(removalCount, 0)
    }

    func testSelectingQueuedTrackPlaysItWithoutReplacingTheQueue() async {
        let a = track("A"), b = track("B"), c = track("C")
        let engine = QueueEditingTestEngine()
        let playback = PlaybackController(engine: engine, tracks: [a, b, c])
        let library = LibraryController(repository: QueueEditingTestRepository(tracks: [a, b, c]))
        await library.load()
        let model = ClassicPlayerModel(library: library, playback: playback)
        let originalQueue = playback.queue.orderedTracks.map(\.id)
        model.openQueue()
        model.selectQueueTrack(b.id)
        model.selectPressed()

        XCTAssertEqual(playback.currentTrack?.id, b.id)
        XCTAssertEqual(playback.queue.orderedTracks.map(\.id), originalQueue)
        XCTAssertEqual(engine.loadCount, 1)
        XCTAssertEqual(engine.status, .playing)
    }

    private func track(_ title: String) -> Track {
        Track(title: title, artist: "Artist", album: "Album", audioFilename: "\(title).mp3")
    }

    private func makeModel() async -> ClassicPlayerModel {
        let library = LibraryController(repository: QueueEditingTestRepository())
        await library.load()
        return ClassicPlayerModel(library: library, playback: PlaybackController(engine: QueueEditingTestEngine()))
    }
}

private actor QueueEditingTestRepository: TrackRepository {
    private let storedTracks: [Track]
    private(set) var removalCount = 0
    init(tracks: [Track] = []) { storedTracks = tracks }
    func tracks() async throws -> [Track] { storedTracks }
    func importTracks(from urls: [URL]) async throws -> TrackImportReport { await TrackImportReport(imported: []) }
    func removeTrack(id: UUID) async throws { removalCount += 1 }
}

private actor QueueEditingTestSessionStore: PlaybackSessionStore {
    private var session: PlaybackSession?
    func load() async -> PlaybackSession? { session }
    func save(_ session: PlaybackSession) async { self.session = session }
    func savedSession() -> PlaybackSession? { session }
}

@MainActor
private final class QueueEditingTestEngine: AudioPlayback {
    nonisolated deinit {}
    var status: AudioPlaybackStatus = .idle
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 100
    var onEvent: (@MainActor @Sendable (AudioPlaybackEvent) -> Void)?
    var onStateChange: (@MainActor @Sendable () -> Void)?
    private(set) var loadCount = 0
    func load(_ track: Track) throws { loadCount += 1; status = .ready; elapsed = 0; onStateChange?() }
    func play() throws { status = .playing; onStateChange?() }
    func pause() { status = .paused; onStateChange?() }
    func seek(to seconds: TimeInterval) throws { elapsed = seconds; onStateChange?() }
    func stop() { status = .idle; elapsed = 0; onStateChange?() }
}
