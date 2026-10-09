import XCTest
@testable import vipod

final class YouTubeDownloadControllerTests: XCTestCase {
    @MainActor
    func testSavedReceiptUsesWinningFallbackFormatAndSurvivesNextURLTyping() async throws {
        let winning = YouTubeAudioFormat(
            formatID: "fallback-aac", extensionName: "m4a", protocolName: "https",
            audioCodec: "mp4a.40.2", videoCodec: "none",
            url: URL(string: "https://media.example.test/fallback")!, httpHeaders: [:],
            filesize: nil, filesizeApprox: 2_400_000, bitrate: 96
        )
        let extraction = YouTubeExtractionResult(
            id: "abcdefghijk", title: "Video", format: winning, formats: [winning],
            webkitJSCChallengeCalls: 0, webkitJSCChallengeSuccesses: 0,
            duration: 90, thumbnail: nil, channel: nil, uploadDate: nil, music: nil
        )
        let track = Track(title: "Saved fallback", audioFilename: "saved.m4a")
        let settled = expectation(description: "save completes")
        let taskController = YouTubeDownloadController(onJobSettled: { settled.fulfill() }) { _, _ in
            YouTubeAudioImportOutcome(track: track, extraction: extraction, cancellationArrivedAfterCommit: false)
        }
        taskController.urlText = "https://youtu.be/abcdefghijk"
        taskController.submit()
        await fulfillment(of: [settled], timeout: 5)

        XCTAssertEqual(taskController.savedTrackReceipt, track)
        XCTAssertEqual(taskController.savedReceipt?.format, "M4A / mp4a.40.2")
        XCTAssertEqual(taskController.savedReceipt?.bitrate, 96)
        XCTAssertNil(taskController.savedReceipt?.exactBytes)
        XCTAssertEqual(taskController.savedReceipt?.approximateBytes, 2_400_000)
        taskController.urlText = "https://youtu.be/zzzzzzzzzzz"
        XCTAssertEqual(taskController.savedReceipt?.track, track)
    }

    @MainActor
    func testChangedURLWhileAnalysisSuspendedDiscardsOldPreview() async throws {
        let harness = DownloadControllerHarness(suspendsAnalysis: true)
        let settled = expectation(description: "stale analysis settles")
        harness.onSettled = { settled.fulfill() }
        let controller = harness.makeController()
        defer { harness.resumeAllWithCancellation() }

        controller.urlText = "https://youtu.be/abcdefghijk"
        controller.submit()
        await fulfillment(of: [harness.analysisStarted], timeout: 5)
        controller.urlText = "https://youtu.be/zzzzzzzzzzz"
        harness.finishAnalysis(videoID: "abcdefghijk")
        await fulfillment(of: [settled], timeout: 5)

        XCTAssertEqual(harness.analysisCount, 1)
        XCTAssertFalse(controller.previewExists)
        XCTAssertEqual(controller.urlText, "https://youtu.be/zzzzzzzzzzz")
        XCTAssertEqual(controller.state, .ready)
    }

    @MainActor
    func testWrongOperationAndOldAttemptProgressAreIgnoredAndNewAttemptResetsToIndeterminate() async throws {
        let harness = DownloadControllerHarness()
        let analysisSettled = expectation(description: "analysis settles")
        harness.onSettled = { analysisSettled.fulfill() }
        let controller = harness.makeController()
        defer { harness.resumeAllWithCancellation() }
        controller.urlText = "https://youtu.be/abcdefghijk"
        controller.submit()
        await fulfillment(of: [analysisSettled], timeout: 5)

        let downloadStarted = expectation(description: "download starts")
        let downloadSettled = expectation(description: "download settles")
        harness.onSettled = { downloadSettled.fulfill() }
        harness.onDownloadStarted = { downloadStarted.fulfill() }
        controller.downloadPreview()
        await fulfillment(of: [downloadStarted], timeout: 5)
        let prepared = try XCTUnwrap(harness.prepared)
        harness.emitProgress(operationID: UUID(), attempt: 99, completed: 4, expected: 4)
        XCTAssertNil(controller.transferProgress, "An event for another operation cannot become visible.")

        harness.emitProgress(operationID: prepared.operationID, attempt: 1, completed: 5_000, expected: 4_000)
        XCTAssertEqual(controller.transferProgress?.fractionCompleted, 1, "Known progress is clamped at completion.")
        harness.emitProgress(operationID: prepared.operationID, attempt: 0, completed: 3_000, expected: 4_000)
        XCTAssertEqual(controller.transferProgress?.attempt, 1, "A late callback from the previous attempt cannot rewind progress.")

        harness.emitProgress(operationID: prepared.operationID, attempt: 2, completed: 300, expected: nil)
        XCTAssertEqual(controller.transferProgress?.attempt, 2)
        XCTAssertNil(controller.transferProgress?.fractionCompleted, "The new attempt starts with unknown-length indeterminate progress.")
        harness.emitProgress(operationID: prepared.operationID, attempt: 1, completed: 4_000, expected: 4_000)
        XCTAssertEqual(controller.transferProgress?.attempt, 2, "An older attempt cannot replace the reset attempt.")

        harness.finishDownload(outcome: harness.outcome())
        await fulfillment(of: [downloadSettled], timeout: 5)
        XCTAssertEqual(controller.savedTrackReceipt?.title, "Harness Saved Track")
        XCTAssertNil(controller.transferProgress)
        XCTAssertEqual(controller.urlText, "")
        controller.urlText = "https://youtu.be/zzzzzzzzzzz"
        XCTAssertEqual(controller.savedReceipt?.track.title, "Harness Saved Track")
    }

    @MainActor
    func testFailureRetainsPreparedPreviewAndRetryReusesAnalysis() async throws {
        let harness = DownloadControllerHarness()
        let analysisSettled = expectation(description: "analysis settles")
        harness.onSettled = { analysisSettled.fulfill() }
        let controller = harness.makeController()
        defer { harness.resumeAllWithCancellation() }
        controller.urlText = "https://youtu.be/abcdefghijk"
        controller.submit()
        await fulfillment(of: [analysisSettled], timeout: 5)

        let firstStarted = expectation(description: "first transfer starts")
        let firstSettled = expectation(description: "first transfer fails")
        harness.onDownloadStarted = { firstStarted.fulfill() }
        harness.onSettled = { firstSettled.fulfill() }
        harness.failNextDownload = true
        controller.downloadPreview()
        await fulfillment(of: [firstStarted], timeout: 5)
        harness.failDownload()
        await fulfillment(of: [firstSettled], timeout: 5)
        XCTAssertTrue(controller.previewExists)
        XCTAssertEqual(controller.urlText, "https://youtu.be/abcdefghijk")
        guard case .failed = controller.state else { return XCTFail("Expected a retryable transfer failure.") }

        let retryStarted = expectation(description: "prepared transfer retries")
        let retrySettled = expectation(description: "retry succeeds")
        harness.onDownloadStarted = { retryStarted.fulfill() }
        harness.onSettled = { retrySettled.fulfill() }
        controller.retry()
        await fulfillment(of: [retryStarted], timeout: 5)
        XCTAssertEqual(harness.analysisCount, 1, "Retry must reuse the prepared extraction instead of analyzing again.")
        harness.finishDownload(outcome: harness.outcome())
        await fulfillment(of: [retrySettled], timeout: 5)
        XCTAssertEqual(controller.savedTrackReceipt?.title, "Harness Saved Track")
    }

    @MainActor
    func testCancelDuringHeldTransferKeepsPreviewAndInputForRetry() async throws {
        let harness = DownloadControllerHarness()
        let analysisSettled = expectation(description: "analysis settles")
        harness.onSettled = { analysisSettled.fulfill() }
        let controller = harness.makeController()
        defer { harness.resumeAllWithCancellation() }
        controller.urlText = "https://youtu.be/abcdefghijk"
        controller.submit()
        await fulfillment(of: [analysisSettled], timeout: 5)

        let started = expectation(description: "held transfer starts")
        let cancelled = expectation(description: "held transfer cancellation settles")
        harness.onDownloadStarted = { started.fulfill() }
        harness.onSettled = { cancelled.fulfill() }
        controller.downloadPreview()
        await fulfillment(of: [started], timeout: 5)
        controller.cancel()
        await fulfillment(of: [cancelled], timeout: 5)

        XCTAssertTrue(controller.previewExists)
        XCTAssertEqual(controller.urlText, "https://youtu.be/abcdefghijk")
        XCTAssertEqual(controller.state, .cancelled)
        XCTAssertFalse(controller.isBusy)
    }

    @MainActor
    func testCommittedTrackReturnedAfterLateCancellationWinsAndIsMarkedInReceipt() async throws {
        let harness = DownloadControllerHarness()
        let analysisSettled = expectation(description: "analysis settles")
        harness.onSettled = { analysisSettled.fulfill() }
        let controller = harness.makeController()
        defer { harness.resumeAllWithCancellation() }
        controller.urlText = "https://youtu.be/abcdefghijk"
        controller.submit()
        await fulfillment(of: [analysisSettled], timeout: 5)

        let started = expectation(description: "commit result is held")
        let settled = expectation(description: "committed result settles")
        harness.ignoreCancellation = true
        harness.onDownloadStarted = { started.fulfill() }
        harness.onSettled = { settled.fulfill() }
        controller.downloadPreview()
        await fulfillment(of: [started], timeout: 5)
        controller.cancel()
        harness.finishDownload(outcome: harness.outcome())
        await fulfillment(of: [settled], timeout: 5)

        XCTAssertEqual(controller.savedTrackReceipt?.title, "Harness Saved Track")
        XCTAssertEqual(controller.savedReceipt?.track.title, "Harness Saved Track")
        XCTAssertTrue(controller.receiptCancellationArrivedAfterCommit)
        XCTAssertEqual(controller.state, .completed(harness.track, cancellationArrivedAfterCommit: true))
    }
}

@MainActor
private final class DownloadControllerHarness {
    private(set) var analysisCount = 0
    private(set) var prepared: YouTubePreparedDownload?
    private var analysisContinuation: CheckedContinuation<YouTubePreparedDownload, Error>?
    private var downloadContinuation: CheckedContinuation<YouTubeAudioImportOutcome, Error>?
    private var progressHandler: (@MainActor (YouTubeAudioImportService.DownloadProgress) -> Void)?
    var onSettled: (@MainActor () -> Void)?
    var onDownloadStarted: (@MainActor () -> Void)?
    var failNextDownload = false
    var ignoreCancellation = false
    let analysisStarted = XCTestExpectation(description: "analysis suspension entered")
    let track = Track(title: "Harness Saved Track", audioFilename: "harness.m4a")

    func makeController() -> YouTubeDownloadController {
        YouTubeDownloadController(onJobSettled: { [weak self] in self?.onSettled?() }, analyze: { [weak self] video in
            guard let self else { throw CancellationError() }
            self.analysisCount += 1
            if self.analysisCount == 1 && self.suspendsAnalysis {
                self.analysisStarted.fulfill()
                return try await withCheckedThrowingContinuation { self.analysisContinuation = $0 }
            }
            let value = Self.prepared(videoID: video.videoID)
            self.prepared = value
            return value
        }, downloadPrepared: { [weak self] prepared, _, progress in
            guard let self else { throw CancellationError() }
            self.prepared = prepared
            self.progressHandler = progress
            self.onDownloadStarted?()
            if self.failNextDownload {
                self.failNextDownload = false
                return try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { self.downloadContinuation = $0 }
                } onCancel: {
                    Task { @MainActor [weak self] in self?.cancelDownload() }
                }
            }
            if self.ignoreCancellation {
                return try await withCheckedThrowingContinuation { self.downloadContinuation = $0 }
            }
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { self.downloadContinuation = $0 }
            } onCancel: {
                Task { @MainActor [weak self] in self?.cancelDownload() }
            }
        })
    }

    private var suspendsAnalysis = false

    init(suspendsAnalysis: Bool = false) { self.suspendsAnalysis = suspendsAnalysis }

    func finishAnalysis(videoID: String) {
        let prepared = Self.prepared(videoID: videoID)
        self.prepared = prepared
        let continuation = analysisContinuation
        analysisContinuation = nil
        continuation?.resume(returning: prepared)
    }

    func emitProgress(operationID: UUID, attempt: Int, completed: Int64, expected: Int64?) {
        progressHandler?(.init(operationID: operationID, attempt: attempt, completedBytes: completed, expectedBytes: expected))
    }

    func finishDownload(outcome: YouTubeAudioImportOutcome) {
        let continuation = downloadContinuation
        downloadContinuation = nil
        continuation?.resume(returning: outcome)
    }

    func failDownload() {
        let continuation = downloadContinuation
        downloadContinuation = nil
        continuation?.resume(throwing: URLError(.networkConnectionLost))
    }

    func cancelDownload() {
        let continuation = downloadContinuation
        downloadContinuation = nil
        continuation?.resume(throwing: CancellationError())
    }

    func resumeAllWithCancellation() {
        let analysis = analysisContinuation
        analysisContinuation = nil
        analysis?.resume(throwing: CancellationError())
        cancelDownload()
    }

    func outcome() -> YouTubeAudioImportOutcome {
        YouTubeAudioImportOutcome(track: track, extraction: Self.extraction(), cancellationArrivedAfterCommit: false)
    }

    private static func prepared(videoID: String) -> YouTubePreparedDownload {
        let extraction = extraction(videoID: videoID)
        let effective = YouTubeEffectiveMetadata(title: "Harness Saved Track", videoTitle: "Harness Video")
        let preview = YouTubeVideoPreview(videoID: videoID, videoTitle: "Harness Video", duration: 30, thumbnailURL: nil, channel: nil, uploadDate: nil, effectiveMetadata: effective, formats: [])
        return YouTubePreparedDownload(preview: preview, operationID: UUID(), extractedAt: Date(), extraction: extraction)
    }

    private static func extraction(videoID: String = "abcdefghijk") -> YouTubeExtractionResult {
        let format = YouTubeAudioFormat(formatID: "harness-aac", extensionName: "m4a", protocolName: "https", audioCodec: "mp4a.40.2", videoCodec: "none", url: URL(string: "https://media.example.test/audio")!, httpHeaders: [:], filesize: 4_000, bitrate: 128)
        return YouTubeExtractionResult(id: videoID, title: "Harness Video", format: format, formats: [format], webkitJSCChallengeCalls: 0, webkitJSCChallengeSuccesses: 0, duration: 30, thumbnail: nil, channel: nil, uploadDate: nil, music: nil)
    }
}
