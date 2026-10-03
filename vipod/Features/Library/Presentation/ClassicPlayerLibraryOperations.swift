import Foundation
import Observation

@MainActor @Observable
final class ClassicPlayerLibraryOperations {
    private let library: LibraryController
    private let playback: PlaybackController
    private var didStart = false

    var importSummary: String?
    var importFailures: [String] = []
    var presentationError: String?
    private(set) var loadFailed = false

    init(library: LibraryController, playback: PlaybackController) {
        self.library = library
        self.playback = playback
    }

    nonisolated deinit {}

    func start() async {
        guard !didStart else { return }
        didStart = true
        if library.tracks.isEmpty { await library.load() }
        if library.errorMessage == nil { await playback.restoreSession(after: library.tracks) }
        loadFailed = library.errorMessage != nil
    }

    func retryLoad() async {
        guard !library.isLoading else { return }
        loadFailed = false
        await library.load()
        if library.errorMessage == nil { await playback.restoreSession(after: library.tracks) }
        loadFailed = library.errorMessage != nil
    }

    func removeTrack(_ track: Track) async -> Bool {
        guard !library.isLoading, !library.isImporting, !library.isRemoving else { return false }
        presentationError = nil
        library.clearError()
        let removed = await library.removeTrack(id: track.id)
        if removed {
            playback.removeTrack(id: track.id)
        } else if let error = library.errorMessage {
            presentationError = error
        }
        return removed
    }

    func importFiles(from urls: [URL]) async {
        guard !urls.isEmpty else { return }
        presentationError = nil
        let previousReport = library.lastImportReport
        library.clearError()
        let accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
        // Keep every selected URL so the repository can report per-file failures.
        await library.importTracks(from: urls)
        if !library.tracks.isEmpty { loadFailed = false }
        if let report = library.lastImportReport, !sameReport(report, previousReport) {
            let count = report.imported.count
            importSummary = report.wasCancelled
                ? String(localized: "Import was cancelled.")
                : String.localizedStringWithFormat(String(localized: "%lld imported, %lld failed"), count, report.failures.count)
            importFailures = report.failures.map(\.filename)
        } else {
            importSummary = nil
            importFailures = []
            presentationError = String(localized: "The selected files could not be imported. Try again.")
        }
    }

    func importerCancelled() {
        // Cancellation is intentionally a no-op: no import report or error is fabricated.
    }

    func importerFailed() {
        presentationError = String(localized: "The selected files could not be imported. Try again.")
    }

    private func sameReport(_ lhs: TrackImportReport, _ rhs: TrackImportReport?) -> Bool {
        guard let rhs else { return false }
        return lhs.wasCancelled == rhs.wasCancelled
            && lhs.imported.map(\.id) == rhs.imported.map(\.id)
            && lhs.failures.map(\.id) == rhs.failures.map(\.id)
    }
}
