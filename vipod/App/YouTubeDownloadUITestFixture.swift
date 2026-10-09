#if DEBUG && os(iOS)
import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class YouTubeDownloadUITestFixture {
    enum Stage: String {
        case knownTransfer = "known-transfer"
        case unknownTransfer = "unknown-transfer"
        case tagging
        case importing
        case completed
        case cancelled
    }

    private(set) var stage: Stage = .knownTransfer
    private(set) var currentAttempt = 1
    private var generation = 0
    private var continuation: CheckedContinuation<Void, Error>?
    private let library: LibraryController
    private(set) var canAdvance = false

    init(library: LibraryController) { self.library = library }

    func reset() {
        guard continuation == nil else { return }
        generation &+= 1
        currentAttempt = 1
        stage = .knownTransfer
        canAdvance = false
    }

    func importFile(_ url: URL) async -> TrackImportReport? { await library.importTracks(from: [url]) }

    func advance() {
        guard canAdvance, let pending = continuation else { return }
        let resumed = pending
        continuation = nil
        canAdvance = false
        switch stage {
        case .knownTransfer:
            currentAttempt = 2
            stage = .unknownTransfer
        case .unknownTransfer:
            stage = .tagging
        case .tagging:
            stage = .importing
        case .importing:
            stage = .completed
        case .completed, .cancelled:
            return
        }
        resumed.resume()
    }

    func cancel() {
        generation &+= 1
        stage = .cancelled
        let resumed = continuation
        continuation = nil
        canAdvance = false
        resumed?.resume(throwing: CancellationError())
    }

    func waitAtCurrentGate() async throws {
        let token = generation
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard token == generation, stage != .cancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                self.canAdvance = true
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancelOperation() {
        cancel()
    }

    static let videoID = "abcdefghijk"
    static let receiptTrackTitle = "Fixture Track Title"
}
#endif
