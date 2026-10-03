import XCTest
@testable import vipod

@MainActor
final class PlaybackSessionPersistenceTests: XCTestCase {
    private func track(_ title: String) -> Track { Track(title: title, audioFilename: "\(title).mp3") }

    func testRestoresExactPausedQueueSelectionPositionAndSettingsAfterLibraryLoad() async {
        let tracks = [track("A"), track("B"), track("C")]
        let store = FakePlaybackSessionStore(session: PlaybackSession(
            selectedTrackID: tracks[1].id, elapsed: 42, queueIDs: tracks.map(\.id),
            shuffledIDs: [tracks[2].id, tracks[1].id, tracks[0].id], repeatMode: .all, isShuffled: true
        ))
        let engine = SessionTestAudioPlayback()
        let controller = PlaybackController(engine: engine, sessionStore: store)

        await controller.restoreSession(after: tracks)

        XCTAssertEqual(controller.queue.tracks.map(\.id), tracks.map(\.id))
        XCTAssertEqual(controller.queue.orderedTracks.map(\.id), [tracks[2].id, tracks[1].id, tracks[0].id])
        XCTAssertEqual(controller.currentTrack?.id, tracks[1].id)
        XCTAssertEqual(controller.elapsed, 42)
        XCTAssertEqual(controller.repeatMode, .all)
        XCTAssertTrue(controller.isShuffled)
        XCTAssertEqual(controller.status, .paused)
        XCTAssertEqual(engine.playCount, 0)
    }

    func testRestorePrunesStaleAndDuplicateIDsAndClampsInvalidElapsed() async {
        let tracks = [track("A"), track("B")]
        let store = FakePlaybackSessionStore(session: PlaybackSession(
            selectedTrackID: UUID(), elapsed: .infinity,
            queueIDs: [tracks[0].id, UUID(), tracks[0].id, tracks[1].id],
            shuffledIDs: [tracks[1].id, UUID(), tracks[1].id], repeatMode: .one, isShuffled: true
        ))
        let controller = PlaybackController(engine: SessionTestAudioPlayback(), sessionStore: store)

        await controller.restoreSession(after: tracks)

        XCTAssertEqual(controller.queue.tracks.map(\.id), tracks.map(\.id))
        XCTAssertEqual(controller.queue.orderedTracks.map(\.id), [tracks[1].id, tracks[0].id])
        XCTAssertNil(controller.currentTrack)
        XCTAssertEqual(controller.elapsed, 0)
        XCTAssertEqual(controller.repeatMode, .one)
        XCTAssertTrue(controller.isShuffled)
        XCTAssertNotEqual(controller.status, .playing)
    }

    func testMissingOrCorruptSessionIsSafeAndStartupDoesNotWriteEmptyState() async {
        let store = FakePlaybackSessionStore(session: nil)
        let controller = PlaybackController(engine: SessionTestAudioPlayback(), sessionStore: store)
        await controller.restoreSession(after: [])
        XCTAssertTrue(controller.queue.tracks.isEmpty)
        let writes = await store.savedSessions()
        let missing = await store.load()
        XCTAssertTrue(writes.isEmpty)
        XCTAssertNil(missing)
    }

    func testUserSelectionBeforeRestoreIsNotOverwritten() async {
        let tracks = [track("A"), track("B")]
        let store = FakePlaybackSessionStore(session: PlaybackSession(
            selectedTrackID: tracks[1].id, elapsed: 20, queueIDs: tracks.map(\.id),
            shuffledIDs: [], repeatMode: .off, isShuffled: false
        ))
        let controller = PlaybackController(engine: SessionTestAudioPlayback(), sessionStore: store)
        controller.replaceQueue(with: tracks)
        controller.play(tracks[0])

        await controller.restoreSession(after: tracks)

        XCTAssertEqual(controller.currentTrack?.id, tracks[0].id)
        XCTAssertEqual(controller.status, .playing)
    }

    func testUserActionDuringPendingSessionLoadWins() async {
        let tracks = [track("A"), track("B")]
        let stored = PlaybackSession(selectedTrackID: tracks[1].id, elapsed: 20, queueIDs: tracks.map(\.id),
            shuffledIDs: [], repeatMode: .off, isShuffled: false)
        let store = DelayedPlaybackSessionStore(session: stored)
        let engine = SessionTestAudioPlayback()
        let controller = PlaybackController(engine: engine, sessionStore: store)
        let restoring = Task { await controller.restoreSession(after: tracks) }
        await store.waitUntilLoadStarts()

        controller.replaceQueue(with: tracks)
        controller.play(tracks[0])
        await store.completeLoad()
        await restoring.value

        XCTAssertEqual(controller.currentTrack?.id, tracks[0].id)
        XCTAssertEqual(controller.status, .playing)
        XCTAssertEqual(engine.playCount, 1)
    }

    func testFlushBeforeAndDuringRestorePreservesPreviouslySavedSession() async {
        let tracks = [track("A"), track("B")]
        let seed = PlaybackSession(revision: 70, selectedTrackID: tracks[1].id, elapsed: 31,
            queueIDs: tracks.map(\.id), shuffledIDs: [], repeatMode: .off, isShuffled: false)
        let store = OverwritingDelayedPlaybackSessionStore(session: seed)
        let controller = PlaybackController(engine: SessionTestAudioPlayback(), sessionStore: store)

        await controller.flushSession()
        let beforeRestore = await store.currentSession()
        XCTAssertEqual(beforeRestore, seed)

        let restoring = Task { await controller.restoreSession(after: tracks) }
        await store.waitUntilLoadStarts()
        await controller.flushSession()
        let duringRestore = await store.currentSession()
        XCTAssertEqual(duringRestore, seed)
        await store.completeLoad()
        await restoring.value
    }

    func testUserActionDuringLoadIsSavedAboveLoadedRevision() async {
        let tracks = [track("A"), track("B")]
        let stored = PlaybackSession(revision: 99, selectedTrackID: tracks[1].id, elapsed: 20,
            queueIDs: tracks.map(\.id), shuffledIDs: [], repeatMode: .off, isShuffled: false)
        let store = RevisionedDelayedPlaybackSessionStore(session: stored)
        let engine = SessionTestAudioPlayback()
        let controller = PlaybackController(engine: engine, sessionStore: store)
        let restoring = Task { await controller.restoreSession(after: tracks) }
        await store.waitUntilLoadStarts()

        controller.replaceQueue(with: tracks)
        controller.play(tracks[0])
        await store.completeLoad()
        await restoring.value
        await controller.flushSession()

        let persisted = await store.currentSession()
        XCTAssertEqual(controller.currentTrack?.id, tracks[0].id)
        XCTAssertEqual(controller.status, .playing)
        XCTAssertEqual(persisted?.selectedTrackID, tracks[0].id)
        XCTAssertGreaterThan(persisted?.revision ?? 0, stored.revision)
    }

    func testPauseSeekRepeatAndShufflePersistLatestSnapshot() async {
        let tracks = [track("A"), track("B"), track("C")]
        let store = FakePlaybackSessionStore(session: nil)
        let controller = PlaybackController(engine: SessionTestAudioPlayback(), randomIndex: { _ in 0 }, sessionStore: store)
        controller.replaceQueue(with: tracks)
        await controller.restoreSession(after: tracks)
        controller.play(tracks[1])
        controller.seek(to: 35)
        controller.setRepeatMode(RepeatMode.all)
        controller.toggleShuffle()
        controller.pause()
        await controller.flushSession()

        let persisted = await store.lastSaved()
        XCTAssertEqual(persisted?.selectedTrackID, tracks[1].id)
        XCTAssertEqual(persisted?.elapsed, 35)
        XCTAssertEqual(persisted?.repeatMode, .all)
        XCTAssertEqual(persisted?.isShuffled, true)
        XCTAssertEqual(persisted?.shuffledIDs, controller.queue.orderedTracks.map { $0.id })
    }

    func testFileAdapterAtomicRoundTripAndDeletionSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("session.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = FilePlaybackSessionStore(url: url)
        let value = PlaybackSession(selectedTrackID: UUID(), elapsed: 5, queueIDs: [], shuffledIDs: [], repeatMode: .off, isShuffled: false)

        await store.save(value)

        let restored = await store.load()
        XCTAssertEqual(restored, value)
        try JSONEncoder().encode(value).write(to: url)
        try FileManager.default.removeItem(at: url)
        let deleted = await store.load()
        XCTAssertNil(deleted)
    }

    func testFileAdapterTreatsCorruptDataAsMissing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        try Data("not-json".utf8).write(to: url)
        let store = FilePlaybackSessionStore(url: url)

        let loaded = await store.load()

        XCTAssertNil(loaded)
    }
}

private actor FakePlaybackSessionStore: PlaybackSessionStore {
    let session: PlaybackSession?
    private(set) var saved: [PlaybackSession] = []
    init(session: PlaybackSession?) { self.session = session }
    func load() async -> PlaybackSession? { session }
    func save(_ session: PlaybackSession) async { saved.append(session) }
    func savedSessions() -> [PlaybackSession] { saved }
    func lastSaved() -> PlaybackSession? { saved.last }
}

private actor DelayedPlaybackSessionStore: PlaybackSessionStore {
    private let session: PlaybackSession
    private var loadContinuation: CheckedContinuation<PlaybackSession?, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?

    init(session: PlaybackSession) { self.session = session }
    func load() async -> PlaybackSession? {
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
            startContinuation?.resume()
            startContinuation = nil
        }
    }
    func save(_ session: PlaybackSession) async {}
    func waitUntilLoadStarts() async {
        if loadContinuation != nil { return }
        await withCheckedContinuation { startContinuation = $0 }
    }
    func completeLoad() {
        loadContinuation?.resume(returning: session)
        loadContinuation = nil
    }
}

private actor OverwritingDelayedPlaybackSessionStore: PlaybackSessionStore {
    private var stored: PlaybackSession?
    private var loadContinuation: CheckedContinuation<PlaybackSession?, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?

    init(session: PlaybackSession) { stored = session }
    func load() async -> PlaybackSession? {
        let valueAtLoad = stored
        return await withCheckedContinuation { continuation in
            loadContinuation = continuation
            startContinuation?.resume()
            startContinuation = nil
            pendingLoad = valueAtLoad
        }
    }
    func save(_ session: PlaybackSession) async { stored = session }
    func currentSession() -> PlaybackSession? { stored }
    func waitUntilLoadStarts() async {
        if loadContinuation != nil { return }
        await withCheckedContinuation { startContinuation = $0 }
    }
    func completeLoad() {
        loadContinuation?.resume(returning: pendingLoad)
        loadContinuation = nil
    }
    private var pendingLoad: PlaybackSession?
}

private actor RevisionedDelayedPlaybackSessionStore: PlaybackSessionStore {
    private var stored: PlaybackSession?
    private var loadContinuation: CheckedContinuation<PlaybackSession?, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var pendingLoad: PlaybackSession?

    init(session: PlaybackSession) { stored = session }
    func load() async -> PlaybackSession? {
        pendingLoad = stored
        return await withCheckedContinuation { continuation in
            loadContinuation = continuation
            startContinuation?.resume()
            startContinuation = nil
        }
    }
    func save(_ session: PlaybackSession) async {
        if session.revision > (stored?.revision ?? 0) { stored = session }
    }
    func currentSession() -> PlaybackSession? { stored }
    func waitUntilLoadStarts() async {
        if loadContinuation != nil { return }
        await withCheckedContinuation { startContinuation = $0 }
    }
    func completeLoad() {
        loadContinuation?.resume(returning: pendingLoad)
        loadContinuation = nil
    }
}

@MainActor
private final class SessionTestAudioPlayback: AudioPlayback {
    nonisolated deinit {}
    private(set) var status: AudioPlaybackStatus = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 100
    var onEvent: (@MainActor @Sendable (AudioPlaybackEvent) -> Void)?
    var onStateChange: (@MainActor @Sendable () -> Void)?
    private(set) var playCount = 0
    func load(_ track: Track) throws { status = .ready; elapsed = 0; onStateChange?() }
    func play() throws { playCount += 1; status = .playing; onStateChange?() }
    func pause() { status = .paused; onStateChange?() }
    func seek(to seconds: TimeInterval) throws { elapsed = seconds; onStateChange?() }
    func stop() { status = .idle; elapsed = 0; duration = 0; onStateChange?() }
}
