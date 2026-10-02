import XCTest
@testable import vipod

@MainActor
final class PlaybackControllerTests: XCTestCase {
    private func track(_ title: String) -> Track {
        Track(title: title, audioFilename: "\(title).mp3")
    }

    func testEmptyQueueAndEndBoundariesAndRepeatAllWrap() async {
        var empty = PlaybackQueue()
        XCTAssertNil(empty.next())
        XCTAssertNil(empty.previous())

        let tracks = [track("A"), track("B")]
        var queue = PlaybackQueue(tracks: tracks)
        XCTAssertEqual(queue.next()?.id, tracks[0].id)
        XCTAssertEqual(queue.next()?.id, tracks[1].id)
        XCTAssertNil(queue.next())
        queue.setRepeatMode(.all)
        XCTAssertEqual(queue.next()?.id, tracks[0].id)
        XCTAssertEqual(queue.previous()?.id, tracks[1].id)
    }

    func testRepeatOneAppliesToCompletionButNotExplicitNext() async {
        let tracks = [track("A"), track("B")]
        let engine = FakeAudioPlayback()
        let controller = PlaybackController(engine: engine, tracks: tracks)
        controller.play(tracks[0])
        controller.setRepeatMode(.one)

        engine.send(.completed)
        XCTAssertEqual(controller.currentTrack?.id, tracks[0].id)
        XCTAssertEqual(controller.status, .playing)
        controller.next()
        XCTAssertEqual(controller.currentTrack?.id, tracks[1].id)
    }

    func testShuffleRetainsCurrentIdentityAndContainsEachTrackAfterReplacement() async {
        let old = [track("A"), track("B"), track("C")]
        let engine = FakeAudioPlayback()
        let controller = PlaybackController(engine: engine, tracks: old, randomIndex: { _ in 0 })
        controller.play(old[1])
        controller.toggleShuffle()
        XCTAssertEqual(controller.currentTrack?.id, old[1].id)

        let added = track("D")
        controller.replaceQueue(with: [old[2], added, old[1]])
        XCTAssertEqual(controller.currentTrack?.id, old[1].id)
        XCTAssertEqual(Set(controller.queue.orderedTracks.map(\.id)), Set([old[2], added, old[1]].map(\.id)))
        XCTAssertEqual(controller.queue.orderedTracks.count, 3)
    }

    func testDuplicateTracksAndInvalidShuffleIDsNormalizeToOneExactPermutation() async {
        let first = track("A")
        let second = track("B")
        var queue = PlaybackQueue(tracks: [first, second, first])
        queue.setShuffle(true, orderedIDs: [UUID(), second.id, second.id])

        XCTAssertEqual(queue.tracks.map(\.id), [first.id, second.id])
        XCTAssertEqual(queue.orderedTracks.map(\.id), [second.id, first.id])
        XCTAssertEqual(Set(queue.orderedTracks.map(\.id)), Set([first.id, second.id]))
    }

    func testPreviousAtFirstTrackRestartsAndPausedSkipStaysPaused() async {
        let tracks = [track("A"), track("B")]
        let engine = FakeAudioPlayback()
        let controller = PlaybackController(engine: engine, tracks: tracks)
        controller.play(tracks[0])
        engine.elapsed = 10
        engine.onStateChange?()
        controller.previous()
        XCTAssertEqual(engine.elapsed, 0)

        controller.pause()
        controller.next()
        XCTAssertEqual(controller.currentTrack?.id, tracks[1].id)
        XCTAssertEqual(controller.status, .paused)
    }

    func testCompletionAdvancesAndPlayingAfterQueueExhaustionReloadsCurrentTrack() async {
        let tracks = [track("A"), track("B")]
        let engine = FakeAudioPlayback()
        let controller = PlaybackController(engine: engine, tracks: tracks)
        controller.play(tracks[0])
        engine.send(.completed)
        XCTAssertEqual(controller.currentTrack?.id, tracks[1].id)
        XCTAssertEqual(controller.status, .playing)
        engine.send(.completed)
        XCTAssertEqual(controller.status, .paused)
        controller.play()
        XCTAssertEqual(controller.status, .playing)
        XCTAssertEqual(engine.loaded.last?.id, tracks[1].id)
    }

    func testFailuresInterruptionResumePauseAndRouteDisconnect() async {
        let tracks = [track("A")]
        let engine = FakeAudioPlayback()
        let controller = PlaybackController(engine: engine, tracks: tracks)
        engine.failNextLoad = true
        controller.play(tracks[0])
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertTrue({ if case .failed = controller.status { true } else { false } }())

        controller.play(tracks[0])
        engine.beginInterruption(shouldResume: true)
        XCTAssertEqual(controller.status, .playing)
        controller.pause()
        let playCountAfterPause = engine.playCount
        engine.beginInterruption(shouldResume: true)
        XCTAssertEqual(engine.playCount, playCountAfterPause)
        XCTAssertNotEqual(controller.status, .playing)
        controller.play()
        engine.send(.routeDisconnected)
        XCTAssertEqual(controller.status, .paused)
    }

    func testTrackOutsideQueueFailsAndDoesNotContinuePlayingPreviouslyLoadedAudio() async {
        let queued = track("Queued")
        let unqueued = track("Not in queue")
        let engine = FakeAudioPlayback()
        let controller = PlaybackController(engine: engine, tracks: [queued])
        controller.play(queued)
        let priorPlayCount = engine.playCount

        controller.play(unqueued)

        XCTAssertNotNil(controller.errorMessage)
        XCTAssertNotEqual(engine.status, .playing)
        XCTAssertEqual(engine.playCount, priorPlayCount)
    }

    func testRemovingCurrentTrackStopsWithoutSelectingOrLoadingReplacement() async {
        let tracks = [track("A"), track("B")]
        let engine = FakeAudioPlayback()
        let controller = PlaybackController(engine: engine, tracks: tracks)
        controller.play(tracks[0])
        controller.seek(to: 25)
        let priorLoads = engine.loaded
        let priorPlayCount = engine.playCount
        var currentWasNilWhenStopped = false
        engine.onStop = { currentWasNilWhenStopped = controller.currentTrack == nil }

        controller.removeTrack(id: tracks[0].id)

        XCTAssertTrue(currentWasNilWhenStopped)
        XCTAssertNil(controller.currentTrack)
        XCTAssertEqual(controller.queue.tracks.map(\.id), [tracks[1].id])
        XCTAssertEqual(controller.status, .idle)
        XCTAssertEqual(controller.elapsed, 0)
        XCTAssertEqual(controller.duration, 0)
        XCTAssertEqual(engine.loaded, priorLoads)
        XCTAssertEqual(engine.playCount, priorPlayCount)
        XCTAssertEqual(engine.stopCount, 1)
    }

    func testRemovingLastTrackLeavesNoCurrentSelection() async {
        let onlyTrack = track("Only")
        let engine = FakeAudioPlayback()
        let controller = PlaybackController(engine: engine, tracks: [onlyTrack])
        controller.play(onlyTrack)

        controller.removeTrack(id: onlyTrack.id)

        XCTAssertTrue(controller.queue.tracks.isEmpty)
        XCTAssertNil(controller.currentTrack)
        XCTAssertEqual(controller.status, .idle)
    }

    func testRemovingNonCurrentTrackPreservesActivePlaybackAndShuffleOrder() async {
        let tracks = [track("A"), track("B"), track("C"), track("D")]
        let engine = FakeAudioPlayback()
        let controller = PlaybackController(engine: engine, tracks: tracks, randomIndex: { _ in 0 })
        controller.play(tracks[2])
        controller.toggleShuffle()
        controller.seek(to: 37)
        let current = controller.currentTrack
        let status = controller.status
        let elapsed = controller.elapsed
        let loaded = engine.loaded
        let playCount = engine.playCount
        let orderWithoutRemoved = controller.queue.orderedTracks.map(\.id).filter { $0 != tracks[0].id }

        controller.removeTrack(id: tracks[0].id)

        XCTAssertEqual(controller.currentTrack?.id, current?.id)
        XCTAssertEqual(controller.status, status)
        XCTAssertEqual(controller.elapsed, elapsed)
        XCTAssertEqual(engine.loaded, loaded)
        XCTAssertEqual(engine.playCount, playCount)
        XCTAssertEqual(controller.queue.orderedTracks.map(\.id), orderWithoutRemoved)
        XCTAssertTrue(controller.isShuffled)
    }
}

@MainActor
private final class FakeAudioPlayback: AudioPlayback {
    nonisolated deinit {}

    private(set) var status: AudioPlaybackStatus = .idle
    var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 120
    var onEvent: (@MainActor @Sendable (AudioPlaybackEvent) -> Void)?
    var onStateChange: (@MainActor @Sendable () -> Void)?
    private(set) var loaded: [Track] = []
    var failNextLoad = false
    private var loadedTrack: Track?
    private(set) var playCount = 0
    private(set) var stopCount = 0
    var onStop: (() -> Void)?

    func load(_ track: Track) throws {
        if failNextLoad { failNextLoad = false; throw PlaybackError.noTrackLoaded }
        loaded.append(track)
        loadedTrack = track
        elapsed = 0
        status = .ready
        onStateChange?()
    }
    func play() throws {
        guard loadedTrack != nil else { throw PlaybackError.noTrackLoaded }
        playCount += 1
        status = .playing
        onStateChange?()
    }
    func pause() { status = .paused; onStateChange?() }
    func seek(to seconds: TimeInterval) throws { elapsed = seconds; onStateChange?() }
    func stop() { stopCount += 1; onStop?(); loadedTrack = nil; status = .idle; elapsed = 0; duration = 0; onStateChange?() }
    func send(_ event: AudioPlaybackEvent) {
        if case .completed = event { status = .ready; onStateChange?() }
        onEvent?(event)
    }
    func beginInterruption(shouldResume: Bool) {
        status = .interrupted
        onStateChange?()
        onEvent?(.interrupted(shouldResume: shouldResume))
    }
}
