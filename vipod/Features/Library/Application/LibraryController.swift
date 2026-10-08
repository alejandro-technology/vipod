import Foundation
import Observation

@MainActor @Observable
public final class LibraryController {
    public private(set) var tracks: [Track] = []
    public private(set) var isLoading = false
    public private(set) var isImporting = false
    public private(set) var isRemoving = false
    public private(set) var lastImportReport: TrackImportReport?
    public private(set) var errorMessage: String?

    private let repository: any TrackRepository

    public init(repository: any TrackRepository) { self.repository = repository }

    // No actor-isolated cleanup is needed; match PlaybackController's teardown
    // workaround for the current simulator concurrency runtime.
    nonisolated deinit {}

    public func load() async {
        guard !isRemoving else { return }
        isLoading = true
        defer { isLoading = false }
        do { tracks = try await repository.tracks(); errorMessage = nil }
        catch is CancellationError { }
        catch { errorMessage = "The music library could not be loaded." }
    }

    @discardableResult
    public func importTracks(from urls: [URL]) async -> TrackImportReport? {
        guard !urls.isEmpty else { lastImportReport = nil; return nil }
        guard !isRemoving, !isImporting else { return nil }
        lastImportReport = nil
        errorMessage = nil
        isImporting = true
        defer { isImporting = false }
        do {
            let report = try await repository.importTracks(from: urls)
            lastImportReport = report
            do {
                tracks = try await repository.tracks()
                errorMessage = report.failures.isEmpty ? nil : "Some selected files could not be imported."
            } catch {
                errorMessage = "The import completed, but the music library could not be refreshed."
            }
            return report
        } catch is CancellationError {
            let report = TrackImportReport(imported: [], wasCancelled: true)
            lastImportReport = report
            return report
        } catch {
            errorMessage = "The selected files could not be imported or the library could not be saved."
            return nil
        }
    }

    @discardableResult
    public func removeTrack(id: UUID) async -> Bool {
        guard !isLoading, !isImporting, !isRemoving else { return false }
        isRemoving = true
        defer { isRemoving = false }
        do {
            try await repository.removeTrack(id: id)
            tracks.removeAll { $0.id == id }
            errorMessage = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = "The track could not be removed from the library."
            return false
        }
    }

    public func clearError() { errorMessage = nil }
}
