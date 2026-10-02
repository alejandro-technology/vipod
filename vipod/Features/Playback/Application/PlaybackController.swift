import Foundation
import Observation

@MainActor @Observable
public final class PlaybackController {
    public private(set) var queue: PlaybackQueue
    public private(set) var status: AudioPlaybackStatus = .idle
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var errorMessage: String?
    public var currentTrack: Track? { queue.currentTrack }
    public var isShuffled: Bool { queue.isShuffled }
    public var repeatMode: RepeatMode { queue.repeatMode }

    private let engine: any AudioPlayback
    private var randomIndex: (Int) -> Int
    private var wasPlayingBeforeInterruption = false

    public init(engine: any AudioPlayback, tracks: [Track] = [], randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }) {
        self.engine = engine
        self.queue = PlaybackQueue(tracks: tracks)
        self.randomIndex = randomIndex
        engine.onStateChange = { [weak self] in self?.synchronizeEngineState() }
        engine.onEvent = { [weak self] event in self?.handle(event) }
        synchronizeEngineState()
    }

    // No actor-isolated cleanup is needed; avoid the synthesized isolated deinit
    // path that crashes during XCTest teardown on the current simulator runtime.
    nonisolated deinit {}

    public func replaceQueue(with tracks: [Track]) {
        let activeID = currentTrack?.id
        queue.replaceTracks(tracks)
        if let activeID, currentTrack?.id != activeID {
            engine.stop()
            wasPlayingBeforeInterruption = false
            synchronizeEngineState()
        }
    }
    public func play(_ track: Track? = nil) {
        do {
            if let track { try selectAndLoad(track) }
            else if currentTrack == nil, let first = queue.orderedTracks.first { try selectAndLoad(first) }
            else if engine.status == .idle, let currentTrack { try engine.load(currentTrack) }
            try engine.play(); wasPlayingBeforeInterruption = true; errorMessage = nil
            synchronizeEngineState()
        } catch { fail("Playback could not be started.") }
    }
    public func pause() { engine.pause(); wasPlayingBeforeInterruption = false; synchronizeEngineState() }
    public func seek(to seconds: TimeInterval) {
        do { try engine.seek(to: min(max(0, seconds), duration)); errorMessage = nil; synchronizeEngineState() }
        catch { fail("Playback position could not be changed.") }
    }
    public func next() {
        advance(to: queue.next(), shouldPlay: status == .playing)
    }
    public func previous() {
        if elapsed > 3 || queue.currentTrack == nil {
            guard let current = queue.currentTrack else { return }
            start(current, shouldPlay: status == .playing)
            return
        }
        let wasPlaying = status == .playing
        guard let track = queue.previous() else {
            if let currentTrack { start(currentTrack, shouldPlay: wasPlaying) }
            return
        }
        start(track, shouldPlay: wasPlaying)
    }
    public func setRepeatMode(_ mode: RepeatMode) { queue.setRepeatMode(mode) }
    public func toggleShuffle() {
        let ids = queue.tracks.map(\.id)
        var shuffled = ids
        if shuffled.count > 1 {
            for index in stride(from: shuffled.count - 1, through: 1, by: -1) {
                let target = min(max(0, randomIndex(index + 1)), index)
                shuffled.swapAt(index, target)
            }
        }
        queue.setShuffle(!queue.isShuffled, orderedIDs: shuffled)
    }
    public func removeTrack(id: UUID) {
        let wasCurrent = currentTrack?.id == id
        queue.remove(id: id)
        if wasCurrent {
            errorMessage = nil
            wasPlayingBeforeInterruption = false
            engine.stop()
            synchronizeEngineState()
        }
    }
    public func clearError() { errorMessage = nil }

    private func selectAndLoad(_ track: Track) throws {
        guard let selected = queue.select(id: track.id) else { throw PlaybackControllerError.trackNotInQueue }
        try engine.load(selected)
    }
    private func start(_ track: Track, shouldPlay: Bool) {
        do {
            try selectAndLoad(track)
            if shouldPlay { try engine.play() }
            else { engine.pause() }
            wasPlayingBeforeInterruption = shouldPlay
            errorMessage = nil
            synchronizeEngineState()
        } catch { fail("The selected track is unavailable or could not be played.") }
    }
    private func advance(to track: Track?, shouldPlay: Bool) {
        guard let track else {
            if queue.repeatMode == .off, let currentTrack { start(currentTrack, shouldPlay: false) }
            else { engine.stop(); synchronizeEngineState() }
            return
        }
        start(track, shouldPlay: shouldPlay)
    }
    private func handle(_ event: AudioPlaybackEvent) {
        switch event {
        case .completed:
            let track = queue.next(automatically: true)
            advance(to: track, shouldPlay: true)
        case .interrupted(let shouldResume):
            if shouldResume && wasPlayingBeforeInterruption { play() }
            else { wasPlayingBeforeInterruption = false; synchronizeEngineState() }
        case .routeDisconnected: pause()
        }
    }
    private func synchronizeEngineState() {
        status = engine.status
        elapsed = max(0, engine.elapsed)
        duration = max(0, engine.duration)
    }
    private func fail(_ message: String) {
        wasPlayingBeforeInterruption = false
        engine.stop()
        synchronizeEngineState()
        errorMessage = message
        status = .failed(message)
    }
}

private enum PlaybackControllerError: Error { case trackNotInQueue }
