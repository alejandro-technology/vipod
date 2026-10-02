import XCTest
import Observation
@testable import vipod

@MainActor
final class ClassicPlayerLibraryOperationsTests: XCTestCase {
    func testStartIsIdempotentAndRetryRecoversFromLoadFailure() async {
        let first = track("First")
        let repository = OperationsRepository(tracks: [first], loadFailures: 1)
        let model = makeModel(repository)

        await model.start()
        XCTAssertTrue(model.loadFailed)
        let firstLoadCount = await repository.loadCount()
        XCTAssertEqual(firstLoadCount, 1)
        await model.start()
        let repeatedLoadCount = await repository.loadCount()
        XCTAssertEqual(repeatedLoadCount, 1)

        await model.retryLoad()
        XCTAssertFalse(model.loadFailed)
        XCTAssertEqual(model.library.tracks, [first])
        let retryLoadCount = await repository.loadCount()
        XCTAssertEqual(retryLoadCount, 2)
    }

    func testImportSummarizesPartialSuccessAndReplacesVisibleLibraryRows() async throws {
        let old = track("Old")
        let added = track("Added")
        let report = TrackImportReport(imported: [added], failures: [TrackImportFailure(filename: "broken.mp3", message: "Invalid")])
        let repository = OperationsRepository(tracks: [old])
        let model = makeModel(repository)
        await model.library.load()
        model.navigation.push(.songs)
        XCTAssertEqual(model.rows.map(\.title), ["Old"])
        await repository.configureImport(report: report, tracksAfterImport: [old, added])

        await model.importFiles(from: [URL(fileURLWithPath: "/tmp/selected.mp3")])

        XCTAssertEqual(model.library.tracks, [old, added])
        XCTAssertEqual(model.rows.map(\.title), ["Old", "Added"])
        XCTAssertEqual(model.importSummary, "1 imported, 1 failed")
        XCTAssertEqual(model.importFailures, ["broken.mp3"])
        XCTAssertNil(model.presentationError)
        guard case .play(_, let queue) = try XCTUnwrap(model.rows.last).action else { return XCTFail("Expected play action") }
        XCTAssertEqual(queue, [old, added])
    }

    func testImportFailureCancellationAndEmptySelectionDoNotFabricateStaleResults() async {
        let repository = OperationsRepository(tracks: [])
        let model = makeModel(repository)
        await model.library.load()
        await repository.configureImport(report: nil, tracksAfterImport: [], fails: true)
        await model.importFiles(from: [URL(fileURLWithPath: "/tmp/fail.mp3")])
        XCTAssertNotNil(model.presentationError)
        XCTAssertNil(model.importSummary)

        model.presentationError = nil
        model.importerCancelled()
        XCTAssertNil(model.presentationError)
        XCTAssertNil(model.importSummary)
        await model.importFiles(from: [])
        XCTAssertNil(model.presentationError)
        XCTAssertNil(model.importSummary)
    }

    func testCancelledImportAndUnchangedReportHaveDistinctPublicResults() async {
        let imported = track("Imported")
        let report = TrackImportReport(imported: [imported])
        let repository = OperationsRepository(tracks: [])
        let model = makeModel(repository)
        await repository.configureImport(report: report, tracksAfterImport: [imported])
        await model.importFiles(from: [URL(fileURLWithPath: "/tmp/imported.mp3")])
        XCTAssertEqual(model.importSummary, "1 imported, 0 failed")

        await repository.configureImport(report: report, tracksAfterImport: [imported])
        await model.importFiles(from: [URL(fileURLWithPath: "/tmp/repeated.mp3")])
        XCTAssertNil(model.importSummary)
        XCTAssertTrue(model.importFailures.isEmpty)
        XCTAssertNotNil(model.presentationError)

        await repository.configureImport(report: nil, tracksAfterImport: [imported], cancels: true)
        await model.importFiles(from: [URL(fileURLWithPath: "/tmp/cancelled.mp3")])
        XCTAssertEqual(model.importSummary, "Import was cancelled.")
        XCTAssertEqual(model.library.lastImportReport?.wasCancelled, true)
    }

    func testReloadWithActiveFilterRefreshesRowsAndEveryPlayQueue() async throws {
        let before = track("Before", artist: "Needle Artist")
        let repository = OperationsRepository(tracks: [before])
        let model = makeModel(repository)
        await model.library.load()
        model.navigation.push(.songs)
        model.filterText = "needle"
        guard case .play(_, let oldQueue) = try XCTUnwrap(model.rows.first).action else { return XCTFail("Expected play action") }
        XCTAssertEqual(oldQueue, [before])

        let refreshed = track("Needle Song", artist: "New Artist")
        let excluded = track("Other", artist: "New Artist")
        await repository.setTracks([refreshed, excluded])
        await model.library.load()

        XCTAssertEqual(model.rows.map(\.title), ["Needle Song"])
        guard case .play(let selected, let newQueue) = try XCTUnwrap(model.rows.first).action else { return XCTFail("Expected play action") }
        XCTAssertEqual(selected, refreshed)
        XCTAssertEqual(newQueue, [refreshed])
    }

    func testPublicFacadeForwardsObservationOfOperationState() {
        let model = makeModel(OperationsRepository(tracks: []))
        let changed = expectation(description: "Forwarded operation state changed")
        withObservationTracking {
            _ = model.importSummary
            _ = model.presentationError
        } onChange: {
            changed.fulfill()
        }

        model.importSummary = "Imported"
        model.presentationError = "Failed"

        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 0), .completed)
        XCTAssertEqual(model.importSummary, "Imported")
        XCTAssertEqual(model.presentationError, "Failed")
    }

    func testSuccessfulImportClearsPriorLoadFailureAndRefreshesFilterImmediately() async {
        let added = track("Fresh")
        let repository = OperationsRepository(tracks: [], loadFailures: 1)
        let model = makeModel(repository)
        await model.start()
        XCTAssertTrue(model.loadFailed)
        model.navigation.push(.songs)
        model.filterText = "fresh"
        await repository.configureImport(report: TrackImportReport(imported: [added]), tracksAfterImport: [added])

        await model.importFiles(from: [URL(fileURLWithPath: "/tmp/fresh.mp3")])

        XCTAssertFalse(model.loadFailed)
        XCTAssertEqual(model.rows.map(\.title), ["Fresh"])
    }

    private func track(_ title: String, artist: String = "Artist", album: String = "Album") -> Track {
        Track(title: title, artist: artist, album: album, audioFilename: "\(title).mp3")
    }

    private func makeModel(_ repository: OperationsRepository) -> ClassicPlayerModel {
        ClassicPlayerModel(library: LibraryController(repository: repository), playback: PlaybackController(engine: OperationsPlayback()))
    }
}

private actor OperationsRepository: TrackRepository {
    private var storedTracks: [Track]
    private var loadFailures: Int
    private var report: TrackImportReport?
    private var importedTracks: [Track] = []
    private var shouldFailImport = false
    private var cancelsImport = false
    private(set) var loads = 0

    init(tracks: [Track], loadFailures: Int = 0) {
        storedTracks = tracks
        self.loadFailures = loadFailures
    }

    func tracks() async throws -> [Track] {
        loads += 1
        if loadFailures > 0 { loadFailures -= 1; throw RepositoryError.failed }
        return storedTracks
    }

    func importTracks(from urls: [URL]) async throws -> TrackImportReport {
        if shouldFailImport { throw RepositoryError.failed }
        if cancelsImport { throw CancellationError() }
        storedTracks = importedTracks
        if let report { return report }
        return await TrackImportReport(imported: [])
    }

    func removeTrack(id: UUID) async throws {}
    func loadCount() -> Int { loads }
    func configureImport(report: TrackImportReport?, tracksAfterImport: [Track], fails: Bool = false, cancels: Bool = false) {
        self.report = report
        importedTracks = tracksAfterImport
        shouldFailImport = fails
        cancelsImport = cancels
    }
    func setTracks(_ tracks: [Track]) { storedTracks = tracks }
}

private enum RepositoryError: Error { case failed }

@MainActor
private final class OperationsPlayback: AudioPlayback {
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
