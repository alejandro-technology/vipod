import XCTest
@testable import vipod

@MainActor
final class LibraryControllerTests: XCTestCase {
    func testImportRefreshesPersistedLibraryAndSurfacesPartialFailure() async {
        let saved = Track(title: "Imported", audioFilename: "imported.mp3")
        let repository = FakeTrackRepository()
        await repository.configure(report: TrackImportReport(
            imported: [saved],
            failures: [TrackImportFailure(filename: "broken.mp3", message: "Invalid audio")]
        ), tracks: [saved])
        let controller = LibraryController(repository: repository)

        await controller.importTracks(from: [URL(fileURLWithPath: "/tmp/selected.mp3")])

        XCTAssertEqual(controller.tracks, [saved])
        XCTAssertEqual(controller.lastImportReport?.imported.map(\.id), [saved.id])
        XCTAssertEqual(controller.errorMessage, "Some selected files could not be imported.")
        XCTAssertFalse(controller.isImporting)
    }

    func testCancelledImportIsReportedWithoutOverwritingExistingLibrary() async {
        let existing = Track(title: "Existing", audioFilename: "existing.mp3")
        let repository = FakeTrackRepository()
        await repository.configure(cancellation: true, tracks: [existing])
        let controller = LibraryController(repository: repository)
        await controller.load()

        await controller.importTracks(from: [URL(fileURLWithPath: "/tmp/selected.mp3")])

        XCTAssertEqual(controller.tracks, [existing])
        XCTAssertEqual(controller.lastImportReport?.wasCancelled, true)
        XCTAssertFalse(controller.isImporting)
    }

    func testRemovalFailureAndCancellationPreserveLibraryAndResetBusyState() async {
        let existing = Track(title: "Existing", audioFilename: "existing.mp3")
        for cancellation in [false, true] {
            let repository = FakeTrackRepository()
            await repository.configure(tracks: [existing], removalCancellation: cancellation, removalFailure: !cancellation)
            let controller = LibraryController(repository: repository)
            await controller.load()

            let removed = await controller.removeTrack(id: existing.id)

            XCTAssertFalse(removed)
            XCTAssertEqual(controller.tracks, [existing])
            XCTAssertFalse(controller.isRemoving)
            if cancellation { XCTAssertNil(controller.errorMessage) }
            else { XCTAssertEqual(controller.errorMessage, "The track could not be removed from the library.") }
        }
    }

    func testConcurrentRemovalIsRejectedAndRemovalBlocksLoadAndImport() async {
        let existing = Track(title: "Existing", audioFilename: "existing.mp3")
        let repository = FakeTrackRepository()
        await repository.configure(tracks: [existing], suspendRemoval: true)
        let controller = LibraryController(repository: repository)
        await controller.load()

        let firstRemoval = Task { await controller.removeTrack(id: existing.id) }
        await repository.waitForRemovalToStart()
        XCTAssertTrue(controller.isRemoving)
        let duplicateRemoval = await controller.removeTrack(id: existing.id)
        XCTAssertFalse(duplicateRemoval)
        await controller.load()
        await controller.importTracks(from: [URL(fileURLWithPath: "/tmp/selected.mp3")])
        await repository.finishRemoval()

        let firstRemovalSucceeded = await firstRemoval.value
        XCTAssertTrue(firstRemovalSucceeded)
        XCTAssertTrue(controller.tracks.isEmpty)
        XCTAssertFalse(controller.isRemoving)
    }
}

private actor FakeTrackRepository: TrackRepository {
    private var savedTracks: [Track] = []
    private var report: TrackImportReport?
    private var cancellation = false
    private var removalCancellation = false
    private var removalFailure = false
    private var suspendRemoval = false
    private var removalHasStarted = false
    private var removalStarted: CheckedContinuation<Void, Never>?
    private var removalGate: CheckedContinuation<Void, Never>?

    func configure(report: TrackImportReport? = nil, cancellation: Bool = false, tracks: [Track], removalCancellation: Bool = false, removalFailure: Bool = false, suspendRemoval: Bool = false) {
        self.report = report
        self.cancellation = cancellation
        self.removalCancellation = removalCancellation
        self.removalFailure = removalFailure
        self.suspendRemoval = suspendRemoval
        removalHasStarted = false
        savedTracks = tracks
    }

    func tracks() async throws -> [Track] { savedTracks }
    func importTracks(from urls: [URL]) async throws -> TrackImportReport {
        if cancellation { throw CancellationError() }
        if let report { return report }
        return await TrackImportReport(imported: [])
    }
    func removeTrack(id: UUID) async throws {
        if suspendRemoval {
            await withCheckedContinuation { continuation in
                removalHasStarted = true
                removalStarted?.resume()
                removalStarted = nil
                removalGate = continuation
            }
        }
        if removalCancellation { throw CancellationError() }
        if removalFailure { throw RepositoryTestError.removalFailed }
        let tracks = savedTracks
        savedTracks = await MainActor.run { tracks.filter { $0.id != id } }
    }
    func waitForRemovalToStart() async {
        if removalHasStarted { return }
        await withCheckedContinuation { continuation in removalStarted = continuation }
    }
    func finishRemoval() { removalGate?.resume(); removalGate = nil }
}

private enum RepositoryTestError: Error { case removalFailed }
