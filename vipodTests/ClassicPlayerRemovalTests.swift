import XCTest
@testable import vipod

@MainActor
final class ClassicPlayerRemovalTests: XCTestCase {
    func testRemovalIsAvailableOnlyForSelectedFilteredSongInSongsDestination() async {
        let first = makeTrack("First")
        let selected = makeTrack("Selected")
        let repository = RemovalTestRepository(tracks: [first, selected])
        let (model, library, _) = makeModel(repository: repository)
        await library.load()

        XCTAssertFalse(model.canRemoveSelectedTrack)
        model.navigation.push(.albums)
        XCTAssertFalse(model.canRemoveSelectedTrack)
        model.navigation.pop()
        model.navigation.push(.songs)
        model.filterText = "No matching song"
        XCTAssertFalse(model.canRemoveSelectedTrack)
        model.filterText = "Selected"
        model.selectedIndex = 0
        XCTAssertTrue(model.canRemoveSelectedTrack)

        model.requestSelectedTrackRemoval()
        XCTAssertEqual(model.selectedTrackForRemoval, selected)
    }

    func testCancelDoesNotChangeLibraryOrPlaybackQueue() async {
        let track = makeTrack("Keep")
        let repository = RemovalTestRepository(tracks: [track])
        let (model, library, playback) = makeModel(repository: repository, playbackTracks: [track])
        await library.load()
        model.navigation.push(.songs)
        model.requestSelectedTrackRemoval()

        model.cancelTrackRemoval()

        XCTAssertNil(model.selectedTrackForRemoval)
        XCTAssertEqual(library.tracks, [track])
        XCTAssertEqual(playback.queue.tracks, [track])
        let removedIDs = await repository.removedIDs()
        XCTAssertEqual(removedIDs, [])
    }

    func testSuccessfulRemovalStopsCurrentTrackAndUpdatesLibraryAndQueue() async {
        let current = makeTrack("Current")
        let other = makeTrack("Other")
        let repository = RemovalTestRepository(tracks: [current, other])
        let (model, library, playback) = makeModel(repository: repository, playbackTracks: [current, other])
        await library.load()
        playback.play(current)

        await model.removeTrack(current)

        XCTAssertEqual(library.tracks, [other])
        XCTAssertFalse(playback.queue.tracks.contains(current))
        XCTAssertNil(playback.currentTrack)
        XCTAssertEqual(playback.status, .idle)
        let removedIDs = await repository.removedIDs()
        XCTAssertEqual(removedIDs, [current.id])
    }

    func testRemovingNonCurrentTrackPreservesCurrentPlayback() async {
        let current = makeTrack("Current")
        let other = makeTrack("Other")
        let repository = RemovalTestRepository(tracks: [current, other])
        let (model, library, playback) = makeModel(repository: repository, playbackTracks: [current, other])
        await library.load()
        playback.play(current)

        await model.removeTrack(other)

        XCTAssertEqual(library.tracks, [current])
        XCTAssertEqual(playback.currentTrack, current)
        XCTAssertEqual(playback.status, .playing)
        XCTAssertEqual(playback.queue.tracks, [current])
    }

    func testConfirmationTargetRemainsCapturedWhenFilterAndHighlightChange() async throws {
        let first = makeTrack("First")
        let second = makeTrack("Second")
        let repository = RemovalTestRepository(tracks: [first, second])
        let (model, library, _) = makeModel(repository: repository)
        await library.load()
        model.navigation.push(.songs)
        model.selectedIndex = 0
        model.requestSelectedTrackRemoval()
        let capturedTrack = try XCTUnwrap(model.selectedTrackForRemoval)

        model.filterText = "Second"
        model.selectedIndex = 0
        await model.removeTrack(capturedTrack)

        XCTAssertEqual(library.tracks, [second])
        let removedIDs = await repository.removedIDs()
        XCTAssertEqual(removedIDs, [first.id])
    }

    func testRemovingLastHighlightedRowNormalizesSelection() async {
        let first = makeTrack("First")
        let last = makeTrack("Last")
        let repository = RemovalTestRepository(tracks: [first, last])
        let (model, library, _) = makeModel(repository: repository)
        await library.load()
        model.navigation.push(.songs)
        model.selectedIndex = 1

        await model.removeTrack(last)

        XCTAssertEqual(library.tracks, [first])
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.selectedRow?.title, first.title)
    }

    func testEmptySongsDestinationHasNoRemovableTrack() async {
        let repository = RemovalTestRepository(tracks: [])
        let (model, library, _) = makeModel(repository: repository)
        await library.load()
        model.navigation.push(.songs)

        XCTAssertFalse(model.canRemoveSelectedTrack)
        model.requestSelectedTrackRemoval()
        XCTAssertNil(model.selectedTrackForRemoval)
    }

    func testFailedAndCancelledRemovalsLeaveLibraryAndQueueUnchanged() async {
        for mode in [RemovalTestRepository.RemovalMode.failure, .cancelled] {
            let track = makeTrack("Keep")
            let repository = RemovalTestRepository(tracks: [track], mode: mode)
            let (model, library, playback) = makeModel(repository: repository, playbackTracks: [track])
            await library.load()
            playback.play(track)

            await model.removeTrack(track)

            XCTAssertEqual(library.tracks, [track])
            XCTAssertEqual(playback.queue.tracks, [track])
            XCTAssertEqual(playback.currentTrack, track)
            XCTAssertEqual(playback.status, .playing)
            let removedIDs = await repository.removedIDs()
            XCTAssertEqual(removedIDs, [])
            if mode == .cancelled {
                XCTAssertNil(model.presentationError, "Cancellation should not present an error.")
            } else {
                XCTAssertNotNil(model.presentationError, "A failed removal should be presented.")
            }
        }
    }

    func testCancellationAfterFailureClearsStaleLibraryErrorWithoutPresentingIt() async {
        let track = makeTrack("Keep")
        let repository = RemovalTestRepository(tracks: [track], mode: .failure)
        let (model, library, _) = makeModel(repository: repository)
        await library.load()

        await model.removeTrack(track)
        XCTAssertNotNil(library.errorMessage)
        XCTAssertNotNil(model.presentationError)

        await repository.setRemovalMode(.cancelled)
        await model.removeTrack(track)

        XCTAssertNil(library.errorMessage)
        XCTAssertNil(model.presentationError)
        XCTAssertEqual(library.tracks, [track])
    }

    func testRemovalBusyStateDisablesEligibilityAndDoesNotOverlapRequests() async {
        let track = makeTrack("Busy")
        let repository = RemovalTestRepository(tracks: [track], waitsForRemoval: true)
        let (model, library, playback) = makeModel(repository: repository)
        await library.load()
        model.navigation.push(.songs)
        let removal = Task { await model.removeTrack(track) }
        await repository.waitUntilRemovalStarts()

        XCTAssertTrue(library.isRemoving)
        XCTAssertFalse(model.canRemoveSelectedTrack)
        await model.removeTrack(track)
        await repository.finishRemoval()
        await removal.value

        XCTAssertFalse(library.isRemoving)
        XCTAssertTrue(library.tracks.isEmpty)
        XCTAssertEqual(playback.queue.tracks, [])
    }

    private func makeTrack(_ title: String) -> Track {
        Track(title: title, artist: "Artist", album: "Album", audioFilename: "\(title).mp3")
    }

    private func makeModel(
        repository: RemovalTestRepository,
        playbackTracks: [Track] = []
    ) -> (ClassicPlayerModel, LibraryController, PlaybackController) {
        let library = LibraryController(repository: repository)
        let playback = PlaybackController(engine: RemovalTestPlayback(), tracks: playbackTracks)
        return (ClassicPlayerModel(library: library, playback: playback), library, playback)
    }
}

private actor RemovalTestRepository: TrackRepository {
    enum RemovalMode: Equatable, Sendable { case success, failure, cancelled }

    private var storedTracks: [Track]
    private var mode: RemovalMode
    private var waitsForRemoval: Bool
    private var removalStarted: CheckedContinuation<Void, Never>?
    private var releaseRemoval: CheckedContinuation<Void, Never>?
    private var didStartRemoval = false
    private(set) var removedTrackIDs: [UUID] = []

    init(tracks: [Track], mode: RemovalMode = .success, waitsForRemoval: Bool = false) {
        storedTracks = tracks
        self.mode = mode
        self.waitsForRemoval = waitsForRemoval
    }

    func tracks() async throws -> [Track] { storedTracks }
    func importTracks(from urls: [URL]) async throws -> TrackImportReport { await TrackImportReport(imported: []) }

    func removeTrack(id: UUID) async throws {
        didStartRemoval = true
        removalStarted?.resume()
        removalStarted = nil
        if waitsForRemoval {
            await withCheckedContinuation { releaseRemoval = $0 }
            waitsForRemoval = false
        }
        switch mode {
        case .success:
            removedTrackIDs.append(id)
            let tracks = storedTracks
            storedTracks = await MainActor.run { tracks.filter { $0.id != id } }
        case .failure: throw NSError(domain: "RemovalTest", code: 1)
        case .cancelled: throw CancellationError()
        }
    }

    func removedIDs() -> [UUID] { removedTrackIDs }

    func setRemovalMode(_ mode: RemovalMode) { self.mode = mode }

    func waitUntilRemovalStarts() async {
        if didStartRemoval { return }
        await withCheckedContinuation { removalStarted = $0 }
    }

    func finishRemoval() {
        releaseRemoval?.resume()
        releaseRemoval = nil
    }
}

@MainActor
private final class RemovalTestPlayback: AudioPlayback {
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
