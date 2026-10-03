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
    private let sessionStore: (any PlaybackSessionStore)?
    private var randomIndex: (Int) -> Int
    private var wasPlayingBeforeInterruption = false
    private var sessionRevision: UInt64 = 0
    private var userIntentRevision: UInt64 = 0
    private var didAttemptRestore = false
    private var isRestoreInFlight = false
    private var lastCheckpoint = Date.distantPast

    public init(engine: any AudioPlayback, tracks: [Track] = [], randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }, sessionStore: (any PlaybackSessionStore)? = nil) {
        self.engine = engine
        self.sessionStore = sessionStore
        self.queue = PlaybackQueue(tracks: tracks)
        self.randomIndex = randomIndex
        engine.onStateChange = { [weak self] in self?.synchronizeEngineState() }
        engine.onEvent = { [weak self] event in self?.handle(event) }
        synchronizeEngineState()
    }

    public func restoreSession(after tracks: [Track]) async {
        guard !didAttemptRestore, !isRestoreInFlight else { return }
        didAttemptRestore = true
        isRestoreInFlight = true
        let intentAtStart = userIntentRevision
        guard let sessionStore else {
            isRestoreInFlight = false
            return
        }
        let saved = await sessionStore.load()
        if let saved { sessionRevision = max(sessionRevision, saved.revision) }
        guard userIntentRevision == intentAtStart, intentAtStart == 0 else {
            isRestoreInFlight = false
            if userIntentRevision > 0 { persistSession() }
            return
        }
        guard let saved else {
            isRestoreInFlight = false
            return
        }
        let libraryByID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        let restoredTracks = saved.queueIDs.compactMap { id -> Track? in
            guard seen.insert(id).inserted else { return nil }
            return libraryByID[id]
        }
        let selectedID = saved.selectedTrackID.flatMap { id in restoredTracks.contains(where: { $0.id == id }) ? id : nil }
        let safeElapsed = saved.elapsed.isFinite ? max(0, saved.elapsed) : 0
        queue.restore(tracks: restoredTracks, selectedID: selectedID, repeatMode: saved.repeatMode, isShuffled: saved.isShuffled, shuffledIDs: saved.shuffledIDs)
        guard let selectedID, let selected = restoredTracks.first(where: { $0.id == selectedID }) else {
            synchronizeEngineState()
            isRestoreInFlight = false
            persistSession()
            return
        }
        do {
            try engine.load(selected)
            engine.pause()
            try engine.seek(to: min(safeElapsed, max(0, engine.duration.isFinite ? engine.duration : 0)))
        } catch {
            // Keep the saved selection and queue; unavailable audio never advances to another track.
        }
        wasPlayingBeforeInterruption = false
        synchronizeEngineState()
        isRestoreInFlight = false
        persistSession()
    }

    public func flushSession() async {
        guard let sessionStore, didAttemptRestore, !isRestoreInFlight else { return }
        let snapshot = makeSessionSnapshot()
        await sessionStore.save(snapshot)
    }

    // No actor-isolated cleanup is needed; avoid the synthesized isolated deinit
    // path that crashes during XCTest teardown on the current simulator runtime.
    nonisolated deinit {}

    public func replaceQueue(with tracks: [Track]) {
        noteUserIntent()
        let activeID = currentTrack?.id
        queue.replaceTracks(tracks)
        if let activeID, currentTrack?.id != activeID {
            engine.stop()
            wasPlayingBeforeInterruption = false
            synchronizeEngineState()
        }
        persistSession()
    }
    public func play(_ track: Track? = nil) {
        noteUserIntent()
        do {
            if let track { try selectAndLoad(track) }
            else if currentTrack == nil, let first = queue.orderedTracks.first { try selectAndLoad(first) }
            else if engine.status == .idle, let currentTrack { try engine.load(currentTrack) }
            try engine.play(); wasPlayingBeforeInterruption = true; errorMessage = nil
            synchronizeEngineState(); persistSession()
        } catch { fail("Playback could not be started.") }
    }
    public func pause() { noteUserIntent(); engine.pause(); wasPlayingBeforeInterruption = false; synchronizeEngineState(); persistSession() }
    public func seek(to seconds: TimeInterval) {
        noteUserIntent()
        do { try engine.seek(to: min(max(0, seconds), duration)); errorMessage = nil; synchronizeEngineState(); persistSession() }
        catch { fail("Playback position could not be changed.") }
    }
    public func next() {
        noteUserIntent()
        advance(to: queue.next(), shouldPlay: status == .playing)
        persistSession()
    }
    public func previous() {
        noteUserIntent()
        if elapsed > 3 || queue.currentTrack == nil {
            guard let current = queue.currentTrack else { return }
            start(current, shouldPlay: status == .playing)
            persistSession()
            return
        }
        let wasPlaying = status == .playing
        guard let track = queue.previous() else {
            if let currentTrack { start(currentTrack, shouldPlay: wasPlaying) }
            return
        }
        start(track, shouldPlay: wasPlaying)
        persistSession()
    }
    public func setRepeatMode(_ mode: RepeatMode) { noteUserIntent(); queue.setRepeatMode(mode); persistSession() }
    public func toggleShuffle() {
        noteUserIntent()
        let ids = queue.tracks.map(\.id)
        var shuffled = ids
        if shuffled.count > 1 {
            for index in stride(from: shuffled.count - 1, through: 1, by: -1) {
                let target = min(max(0, randomIndex(index + 1)), index)
                shuffled.swapAt(index, target)
            }
        }
        queue.setShuffle(!queue.isShuffled, orderedIDs: shuffled)
        persistSession()
    }
    public func removeTrack(id: UUID) {
        noteUserIntent()
        let wasCurrent = currentTrack?.id == id
        queue.remove(id: id)
        if wasCurrent {
            errorMessage = nil
            wasPlayingBeforeInterruption = false
            engine.stop()
            synchronizeEngineState()
        }
        persistSession()
    }
    public func playNext(_ track: Track) {
        noteUserIntent()
        guard queue.enqueueNext(track) else { return }
        persistSession()
    }
    public func addLast(_ track: Track) {
        noteUserIntent()
        guard queue.addLast(track) else { return }
        persistSession()
    }
    public func moveQueueItem(id: UUID, to index: Int) {
        noteUserIntent()
        guard queue.move(id: id, toVisibleIndex: index) else { return }
        persistSession()
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
            persistSession()
        case .interrupted(let shouldResume):
            if shouldResume && wasPlayingBeforeInterruption { play() }
            else { wasPlayingBeforeInterruption = false; synchronizeEngineState(); persistSession() }
        case .routeDisconnected: pause()
        }
    }
    private func synchronizeEngineState() {
        status = engine.status
        elapsed = max(0, engine.elapsed)
        duration = max(0, engine.duration)
        if status == .playing, Date().timeIntervalSince(lastCheckpoint) >= 5 {
            lastCheckpoint = Date()
            persistSession()
        }
    }

    private func noteUserIntent() { userIntentRevision &+= 1 }

    private func makeSessionSnapshot() -> PlaybackSession {
        sessionRevision &+= 1
        return PlaybackSession(revision: sessionRevision, selectedTrackID: currentTrack?.id,
            elapsed: elapsed.isFinite ? max(0, elapsed) : 0,
            queueIDs: queue.tracks.map(\.id), shuffledIDs: queue.orderedTracks.map(\.id),
            repeatMode: repeatMode, isShuffled: isShuffled)
    }

    private func persistSession() {
        guard let sessionStore, didAttemptRestore, !isRestoreInFlight else { return }
        let snapshot = makeSessionSnapshot()
        Task { await sessionStore.save(snapshot) }
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
