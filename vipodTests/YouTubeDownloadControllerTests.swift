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
        controller.updateMetadataDraft(\.title, value: "Hand-edited title")

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
        XCTAssertEqual(controller.metadataDraft?.title, "Hand-edited title")
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
        XCTAssertEqual(harness.capturedMetadata?.title, "Hand-edited title")
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
        controller.updateMetadataDraft(\.artist, value: "Edited artist")
        XCTAssertEqual(controller.metadataDraft?.artist, "Edited artist")
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

    @MainActor
    func testMusicBrainzApplyUpdatesAvailableDraftFieldsAndPassesExactConfirmationToDownload() async throws {
        let harness = DownloadControllerHarness()
        let search = FakeMusicMetadataSearch()
        let analysisSettled = expectation(description: "analysis settles")
        harness.onSettled = { analysisSettled.fulfill() }
        let controller = harness.makeController(musicMetadataSearch: search)
        defer { harness.resumeAllWithCancellation() }

        controller.urlText = "https://youtu.be/abcdefghijk"
        controller.submit()
        await fulfillment(of: [analysisSettled], timeout: 5)
        let originalSourceTitle = try XCTUnwrap(controller.retainedPreview?.effectiveMetadata.title)

        controller.musicBrainzQuery = "Fixture Search"
        controller.searchMusicBrainz()
        let searchFinished = await waitForCondition { controller.musicBrainzSearchState == .results }
        XCTAssertTrue(searchFinished)
        controller.selectMusicBrainzRecording(search.recording.id)
        controller.selectMusicBrainzRelease(search.release.id)
        let releaseLoaded = await waitForCondition { controller.selectedMusicBrainzRelease != nil }
        XCTAssertTrue(releaseLoaded)
        controller.selectMusicBrainzTrack(try XCTUnwrap(search.release.tracks.first).id)
        XCTAssertEqual(controller.metadataDraft?.title, "MusicBrainz Track", "Selecting a track should immediately fill the editable draft.")
        let artworkLoaded = await waitForCondition { controller.hasMusicBrainzArtwork }
        XCTAssertTrue(artworkLoaded)
        XCTAssertEqual(controller.selectedArtworkSource, .musicBrainz)
        controller.selectArtworkSource(.youtube)
        XCTAssertEqual(controller.selectedArtworkSource, .youtube)
        controller.selectArtworkSource(.musicBrainz)

        controller.updateMetadataDraft(\.title, value: "Confirmed hand edit")
        XCTAssertEqual(controller.retainedPreview?.effectiveMetadata.title, originalSourceTitle, "MusicBrainz and manual edits must not mutate extraction metadata.")
        XCTAssertEqual(controller.metadataDraft?.title, "Confirmed hand edit")
        XCTAssertEqual(controller.metadataDraft?.artist, "MusicBrainz Artist")
        XCTAssertEqual(controller.metadataDraft?.album, "MusicBrainz Album")
        XCTAssertEqual(controller.metadataDraft?.albumArtist, "MusicBrainz Album Artist")
        XCTAssertEqual(controller.metadataDraft?.releaseDate, "2025-04-03")
        XCTAssertEqual(controller.metadataDraft?.genre, "Jazz")
        XCTAssertEqual(controller.metadataDraft?.trackNumber, "4")
        XCTAssertEqual(controller.metadataDraft?.trackNumberTotal, "12")
        XCTAssertEqual(controller.metadataDraft?.discNumber, "2")
        XCTAssertEqual(controller.metadataDraft?.discNumberTotal, "2")

        controller.selectArtworkSource(.youtube)
        let youtubeStarted = expectation(description: "YouTube thumbnail selection reaches download handoff")
        let youtubeSettled = expectation(description: "YouTube thumbnail handoff cancellation settles")
        harness.onDownloadStarted = { youtubeStarted.fulfill() }
        harness.onSettled = { youtubeSettled.fulfill() }
        controller.downloadPreview()
        await fulfillment(of: [youtubeStarted], timeout: 5)
        XCTAssertNil(harness.capturedArtwork, "Choosing YouTube artwork must not pass the MusicBrainz cover override.")
        controller.cancel()
        await fulfillment(of: [youtubeSettled], timeout: 5)

        controller.selectArtworkSource(.musicBrainz)
        let downloadStarted = expectation(description: "confirmed metadata reaches download handoff")
        let downloadSettled = expectation(description: "cancelled handoff settles")
        harness.onDownloadStarted = { downloadStarted.fulfill() }
        harness.onSettled = { downloadSettled.fulfill() }
        controller.downloadPreview()
        await fulfillment(of: [downloadStarted], timeout: 5)
        XCTAssertEqual(harness.capturedMetadata?.title, "Confirmed hand edit")
        XCTAssertEqual(harness.capturedMetadata?.artist, "MusicBrainz Artist")
        XCTAssertEqual(harness.capturedMetadata?.album, "MusicBrainz Album")
        XCTAssertEqual(harness.capturedMetadata?.albumArtist, "MusicBrainz Album Artist")
        XCTAssertEqual(harness.capturedMetadata?.releaseDate, "2025-04-03")
        XCTAssertEqual(harness.capturedMetadata?.genre, "Jazz")
        XCTAssertEqual(harness.capturedMetadata?.trackNumber, 4)
        XCTAssertEqual(harness.capturedMetadata?.trackNumberTotal, 12)
        XCTAssertEqual(harness.capturedMetadata?.discNumber, 2)
        XCTAssertEqual(harness.capturedMetadata?.discNumberTotal, 2)
        XCTAssertEqual(harness.capturedArtwork, search.coverArt)
        controller.cancel()
        await fulfillment(of: [downloadSettled], timeout: 5)
        XCTAssertEqual(controller.metadataDraft?.title, "Confirmed hand edit", "Cancellation retains the draft for retry.")
    }

    @MainActor
    func testApplyingReleaseWithoutArtworkDoesNotReusePreviousReleaseArtwork() async throws {
        try await assertNewReleaseDoesNotReuseArtwork(artworkFails: false)
    }

    @MainActor
    func testApplyingReleaseWithArtworkFailureDoesNotReusePreviousReleaseArtwork() async throws {
        try await assertNewReleaseDoesNotReuseArtwork(artworkFails: true)
    }

    @MainActor
    private func assertNewReleaseDoesNotReuseArtwork(artworkFails: Bool) async throws {
        let harness = DownloadControllerHarness()
        let search = FakeMusicMetadataSearch()
        let analyzed = expectation(description: "analysis settles")
        harness.onSettled = { analyzed.fulfill() }
        let controller = harness.makeController(musicMetadataSearch: search)
        defer { search.finishSecondArtwork(throwing: false); harness.resumeAllWithCancellation() }
        controller.urlText = "https://youtu.be/abcdefghijk"
        controller.submit()
        await fulfillment(of: [analyzed], timeout: 5)
        controller.searchMusicBrainz()
        let searched = await waitForCondition { controller.musicBrainzSearchState == .results }
        XCTAssertTrue(searched)
        controller.selectMusicBrainzRecording(search.recording.id)
        controller.selectMusicBrainzRelease(search.release.id)
        let firstLoaded = await waitForCondition { controller.selectedMusicBrainzRelease?.id == search.release.id }
        XCTAssertTrue(firstLoaded)
        controller.selectMusicBrainzTrack(try XCTUnwrap(search.release.tracks.first).id)
        let firstArtworkLoaded = await waitForCondition { controller.hasMusicBrainzArtwork }
        XCTAssertTrue(firstArtworkLoaded)

        controller.selectMusicBrainzRelease(search.secondRelease.id)
        let secondLoaded = await waitForCondition { controller.selectedMusicBrainzRelease?.id == search.secondRelease.id }
        XCTAssertTrue(secondLoaded)
        controller.selectMusicBrainzTrack(try XCTUnwrap(search.secondRelease.tracks.first).id)
        XCTAssertFalse(controller.hasMusicBrainzArtwork, "Apply must clear the old override before the next cover request starts.")
        let secondArtworkStarted = await waitForCondition { search.secondArtworkContinuation != nil }
        XCTAssertTrue(secondArtworkStarted)
        controller.updateMetadataDraft(\.title, value: "Manual title while artwork loads")
        search.finishSecondArtwork(throwing: artworkFails)
        let artworkSettled = await waitForCondition { !controller.isLoadingMusicBrainzArtwork }
        XCTAssertTrue(artworkSettled)
        XCTAssertFalse(controller.hasMusicBrainzArtwork)
        XCTAssertEqual(controller.metadataDraft?.title, "Manual title while artwork loads")
        XCTAssertEqual(controller.metadataDraft?.album, "Second album")
        controller.updateMetadataDraft(\.artist, value: "Manual artist after artwork failure")

        let started = expectation(description: "final download handoff")
        let settled = expectation(description: "download cancellation settles")
        harness.onDownloadStarted = { started.fulfill() }
        harness.onSettled = { settled.fulfill() }
        controller.downloadPreview()
        await fulfillment(of: [started], timeout: 5)
        XCTAssertNil(harness.capturedArtwork, "Release A's cover must not reach release B's download.")
        XCTAssertEqual(harness.capturedMetadata?.title, "Manual title while artwork loads")
        XCTAssertEqual(harness.capturedMetadata?.artist, "Manual artist after artwork failure")
        XCTAssertEqual(harness.capturedMetadata?.album, "Second album")
        controller.cancel()
        await fulfillment(of: [settled], timeout: 5)
    }

    @MainActor
    func testNewMusicBrainzQueryRejectsAnOlderInFlightResponse() async throws {
        let harness = DownloadControllerHarness()
        let search = DelayedMusicMetadataSearch()
        let analysisSettled = expectation(description: "analysis settles")
        harness.onSettled = { analysisSettled.fulfill() }
        let controller = harness.makeController(musicMetadataSearch: search)
        defer { search.resumeAllWithEmptyResults(); harness.resumeAllWithCancellation() }

        controller.urlText = "https://youtu.be/abcdefghijk"
        controller.submit()
        await fulfillment(of: [analysisSettled], timeout: 5)

        controller.musicBrainzQuery = "older query"
        controller.searchMusicBrainz()
        let firstSearchStarted = await waitForCondition { search.pendingSearchCount == 1 }
        XCTAssertTrue(firstSearchStarted)
        controller.musicBrainzQuery = "newer query"
        controller.searchMusicBrainz()
        let secondSearchStarted = await waitForCondition { search.pendingSearchCount == 2 }
        XCTAssertTrue(secondSearchStarted)

        search.resumeSearch(at: 1, recordings: [search.newerRecording])
        let newerResponseVisible = await waitForCondition { controller.musicBrainzRecordings == [search.newerRecording] }
        XCTAssertTrue(newerResponseVisible)
        search.resumeSearch(at: 0, recordings: [search.olderRecording])
        let bothSearchesReturned = await waitForCondition { search.completedSearchCount == 2 }
        XCTAssertTrue(bothSearchesReturned)
        XCTAssertEqual(controller.musicBrainzRecordings, [search.newerRecording])
    }

    @MainActor
    func testChangingVideoInvalidatesInFlightMusicBrainzResultsAndDraft() async throws {
        let harness = DownloadControllerHarness()
        let search = DelayedMusicMetadataSearch()
        let analysisSettled = expectation(description: "analysis settles")
        harness.onSettled = { analysisSettled.fulfill() }
        let controller = harness.makeController(musicMetadataSearch: search)
        defer { search.resumeAllWithEmptyResults(); harness.resumeAllWithCancellation() }

        controller.urlText = "https://youtu.be/abcdefghijk"
        controller.submit()
        await fulfillment(of: [analysisSettled], timeout: 5)
        controller.searchMusicBrainz()
        let searchStarted = await waitForCondition { search.pendingSearchCount == 1 }
        XCTAssertTrue(searchStarted)

        controller.urlText = "https://youtu.be/zzzzzzzzzzz"
        search.resumeSearch(at: 0, recordings: [search.olderRecording])
        let staleSearchReturned = await waitForCondition { search.completedSearchCount == 1 }
        XCTAssertTrue(staleSearchReturned)
        XCTAssertNil(controller.metadataDraft)
        XCTAssertFalse(controller.previewExists)
        XCTAssertTrue(controller.musicBrainzRecordings.isEmpty)
        XCTAssertEqual(controller.musicBrainzSearchState, .idle)
    }

    @MainActor
    func testMetadataDraftRequiresTitleAndValidTrackAndDiscOrdinals() {
        var draft = YouTubeMetadataDraft(metadata: .init(title: "Song", videoTitle: "Video"))
        XCTAssertNil(draft.validationMessage)
        draft.title = "  "
        XCTAssertEqual(draft.validationMessage, "A title is required before downloading.")
        draft.title = "Song"
        draft.trackNumber = "3"
        draft.trackNumberTotal = "2"
        XCTAssertEqual(draft.validationMessage, "Track total cannot be smaller than its number.")
        draft.trackNumberTotal = "4"
        draft.discNumber = "one"
        XCTAssertEqual(draft.validationMessage, "Disc number must be a positive whole number.")
    }
}

@MainActor
private final class DownloadControllerHarness {
    private(set) var analysisCount = 0
    private(set) var prepared: YouTubePreparedDownload?
    private(set) var capturedMetadata: YouTubeEffectiveMetadata?
    private(set) var capturedArtwork: Data?
    private var analysisContinuation: CheckedContinuation<YouTubePreparedDownload, Error>?
    private var downloadContinuation: CheckedContinuation<YouTubeAudioImportOutcome, Error>?
    private var progressHandler: (@MainActor (YouTubeAudioImportService.DownloadProgress) -> Void)?
    var onSettled: (@MainActor () -> Void)?
    var onDownloadStarted: (@MainActor () -> Void)?
    var failNextDownload = false
    var ignoreCancellation = false
    let analysisStarted = XCTestExpectation(description: "analysis suspension entered")
    let track = Track(title: "Harness Saved Track", audioFilename: "harness.m4a")

    func makeController(musicMetadataSearch: (any YouTubeMusicMetadataSearching)? = nil) -> YouTubeDownloadController {
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
        }, musicMetadataSearch: musicMetadataSearch, downloadPrepared: { [weak self] prepared, metadata, artwork, _, progress in
            guard let self else { throw CancellationError() }
            self.prepared = prepared
            self.capturedMetadata = metadata
            self.capturedArtwork = artwork
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

@MainActor
private final class FakeMusicMetadataSearch: YouTubeMusicMetadataSearching {
    let recording = YouTubeMusicRecording(
        id: "11111111-1111-4111-8111-111111111111", title: "MusicBrainz Recording",
        artist: "MusicBrainz Artist", firstReleaseDate: "2025", genre: "Jazz",
        releases: [YouTubeMusicReleaseSummary(
            id: "22222222-2222-4222-8222-222222222222", title: "MusicBrainz Album",
            artist: "MusicBrainz Album Artist", date: "2025-04-03", trackCount: 12
        ), YouTubeMusicReleaseSummary(
            id: "66666666-6666-4666-8666-666666666666", title: "Second album",
            artist: nil, date: nil, trackCount: 1
        )]
    )
    let release = YouTubeMusicReleaseDetails(
        id: "22222222-2222-4222-8222-222222222222", title: "MusicBrainz Album",
        artist: "MusicBrainz Album Artist", date: "2025-04-03", genre: "Jazz", discTotal: 2,
        tracks: [YouTubeMusicTrack(
            id: "33333333-3333-4333-8333-333333333333", title: "MusicBrainz Track",
            artist: "MusicBrainz Artist", number: 4, numberTotal: 12, discNumber: 2
        )]
    )
    let secondRelease = YouTubeMusicReleaseDetails(
        id: "66666666-6666-4666-8666-666666666666", title: "Second album",
        artist: nil, date: nil, genre: nil, discTotal: 1,
        tracks: [YouTubeMusicTrack(
            id: "77777777-7777-4777-8777-777777777777", title: "Second track",
            artist: nil, number: 1, numberTotal: 1, discNumber: 1
        )]
    )
    let coverArt = Data("deterministic-cover-art".utf8)
    var secondArtworkContinuation: CheckedContinuation<Data?, Error>?

    func searchRecordings(query: String) async throws -> [YouTubeMusicRecording] { [recording] }
    func loadRelease(id: String) async throws -> YouTubeMusicReleaseDetails { id == secondRelease.id ? secondRelease : release }
    func artwork(releaseID: String) async throws -> Data? {
        guard releaseID == secondRelease.id else { return coverArt }
        return try await withCheckedThrowingContinuation { secondArtworkContinuation = $0 }
    }

    func finishSecondArtwork(throwing fails: Bool) {
        let continuation = secondArtworkContinuation
        secondArtworkContinuation = nil
        if fails { continuation?.resume(throwing: URLError(.notConnectedToInternet)) }
        else { continuation?.resume(returning: nil) }
    }
}

@MainActor
private final class DelayedMusicMetadataSearch: YouTubeMusicMetadataSearching {
    private var pendingSearches: [CheckedContinuation<[YouTubeMusicRecording], Error>] = []
    private(set) var completedSearchCount = 0
    var pendingSearchCount: Int { pendingSearches.count }
    let olderRecording = YouTubeMusicRecording(id: "44444444-4444-4444-8444-444444444444", title: "Older response", artist: nil, firstReleaseDate: nil, genre: nil, releases: [])
    let newerRecording = YouTubeMusicRecording(id: "55555555-5555-4555-8555-555555555555", title: "Newer response", artist: nil, firstReleaseDate: nil, genre: nil, releases: [])

    func searchRecordings(query: String) async throws -> [YouTubeMusicRecording] {
        let recordings = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[YouTubeMusicRecording], Error>) in
            pendingSearches.append(continuation)
        }
        completedSearchCount += 1
        return recordings
    }

    func loadRelease(id: String) async throws -> YouTubeMusicReleaseDetails {
        YouTubeMusicReleaseDetails(id: id, title: "Release", artist: nil, date: nil, genre: nil, discTotal: nil, tracks: [])
    }

    func artwork(releaseID: String) async throws -> Data? { nil }

    func resumeSearch(at index: Int, recordings: [YouTubeMusicRecording]) {
        guard pendingSearches.indices.contains(index) else { return }
        pendingSearches.remove(at: index).resume(returning: recordings)
    }

    func resumeAllWithEmptyResults() {
        let pending = pendingSearches
        pendingSearches.removeAll()
        pending.forEach { $0.resume(returning: []) }
    }
}

@MainActor
private func waitForCondition(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
