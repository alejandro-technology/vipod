import XCTest
@testable import vipod

final class YouTubeAudioImportTests: XCTestCase {
    @MainActor
    func testProductionDownloadControllerRejectsInvalidInputWithoutStartingWork() {
        let controller = YouTubeDownloadController { _, _ in
            XCTFail("Invalid input must not start a download.")
            throw CancellationError()
        }
        controller.urlText = "https://www.youtube.com/playlist?list=PL123"
        controller.submit()
        XCTAssertEqual(controller.state, .failed("Enter a valid link to one public YouTube video."))
    }

    @MainActor
    func testControllerCancellationSuppressesStaleProgressAndAllowsRetryOnlyAfterSettlement() async throws {
        var continuations: [CheckedContinuation<YouTubeAudioImportOutcome, Error>] = []
        var progressCallbacks: [@MainActor (YouTubeAudioImportService.Stage) -> Void] = []
        let started = [expectation(description: "first operation started"), expectation(description: "retry operation started")]
        let settled = [expectation(description: "first operation settled"), expectation(description: "retry operation settled")]
        var invocationCount = 0
        let controller = YouTubeDownloadController(onJobSettled: {
            settled[invocationCount - 1].fulfill()
        }) { _, progress in
            invocationCount += 1
            let index = invocationCount - 1
            progressCallbacks.append(progress)
            started[index].fulfill()
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<YouTubeAudioImportOutcome, Error>) in
                continuations.append(continuation)
            }
        }
        controller.urlText = "https://www.youtube.com/watch?v=abcdefghijk"

        controller.submit()
        controller.submit()
        await fulfillment(of: [started[0]], timeout: 5)
        XCTAssertEqual(invocationCount, 1)
        controller.cancel()
        progressCallbacks[0](.importing)
        XCTAssertEqual(controller.state, .cancelling)
        XCTAssertTrue(controller.isBusy)
        XCTAssertEqual(invocationCount, 1, "A new attempt must remain blocked until cancellation settles.")
        continuations[0].resume(throwing: URLError(.cancelled))
        await fulfillment(of: [settled[0]], timeout: 5)
        XCTAssertEqual(controller.state, .cancelled)
        XCTAssertFalse(controller.isBusy)

        controller.retry()
        await fulfillment(of: [started[1]], timeout: 5)
        XCTAssertEqual(invocationCount, 2)
        continuations[1].resume(throwing: YouTubeImportError.runtimeUnavailable)
        await fulfillment(of: [settled[1]], timeout: 5)
        XCTAssertEqual(controller.state, .failed("YouTube extraction needs a restart. Close and reopen VIPOD before trying again."))
    }

    @MainActor
    func testControllerShowsCommittedTrackWhenCancellationArrivesAfterSave() async throws {
        let started = expectation(description: "operation started")
        let settled = expectation(description: "operation settled")
        let track = Track(title: "Saved", audioFilename: "saved.m4a")
        var continuation: CheckedContinuation<YouTubeAudioImportOutcome, Error>?
        let controller = YouTubeDownloadController(onJobSettled: { settled.fulfill() }) { _, _ in
            started.fulfill()
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        controller.urlText = "https://www.youtube.com/watch?v=abcdefghijk"
        controller.submit()
        await fulfillment(of: [started], timeout: 5)
        controller.cancel()
        continuation?.resume(returning: YouTubeAudioImportOutcome(
            track: track,
            extraction: extractionResult("Saved"),
            cancellationArrivedAfterCommit: false
        ))
        await fulfillment(of: [settled], timeout: 5)

        XCTAssertEqual(controller.state, .completed(track, cancellationArrivedAfterCommit: true))
        XCTAssertFalse(controller.isBusy)
    }

    @MainActor
    func testServiceClassifiesDuplicateFromTypedReasonRegardlessOfMessage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vipod-youtube-service-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let downloaded = root.appendingPathComponent("download.m4a")
        try Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]).write(to: downloaded)
        let service = YouTubeAudioImportService(
            extract: { _ in self.extractionResult("Title") },
            download: { request in
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (downloaded, response)
            },
            importFile: { _ in
                TrackImportReport(imported: [], failures: [TrackImportFailure(filename: "anything.m4a", message: "Localized copy changed", reason: .duplicate)])
            }
        )

        do {
            _ = try await service.run(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")), update: { _ in })
            XCTFail("Typed duplicate import should fail with the duplicate classification.")
        } catch let error as YouTubeImportError {
            XCTAssertEqual(YouTubeDownloadController.userMessage(for: error), "This audio is already in your music library.")
        }
    }

    @MainActor
    func testServicePreservesHTTPFailureStatusWithoutImporting() async throws {
        var importCalled = false
        let service = YouTubeAudioImportService(
            extract: { _ in self.extractionResult("Title") },
            download: { request in
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 429, httpVersion: nil, headerFields: nil)!
                return (FileManager.default.temporaryDirectory.appendingPathComponent("unused-download-\(UUID().uuidString)"), response)
            },
            importFile: { _ in
                importCalled = true
                return nil
            }
        )

        do {
            _ = try await service.run(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")), update: { _ in })
            XCTFail("A non-success HTTP response must fail before library import.")
        } catch let error as YouTubeImportError {
            XCTAssertEqual(YouTubeDownloadController.userMessage(for: error), "YouTube is rate-limiting audio requests (HTTP 429). Wait before trying again.")
        }
        XCTAssertFalse(importCalled)
    }

    @MainActor
    func testServiceFallsBackToNextYtDlpRankedAACAfterHTTP403() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vipod-youtube-ranked-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let rejectedDownload = root.appendingPathComponent("rejected.tmp")
        let acceptedDownload = root.appendingPathComponent("accepted.m4a")
        try Data("forbidden response".utf8).write(to: rejectedDownload)
        try Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]).write(to: acceptedDownload)
        let preferred = format("preferred", extension: "m4a", protocol: "https", audio: "mp4a.40.2", video: "none", bitrate: 256, urlPath: "preferred")
        let fallback = format("fallback", extension: "m4a", protocol: "https", audio: "mp4a.40.2", video: "none", bitrate: 128, urlPath: "fallback")
        let result = YouTubeExtractionResult(
            id: "abcdefghijk",
            title: "Title",
            format: preferred,
            formats: [preferred, fallback],
            webkitJSCChallengeCalls: 0,
            webkitJSCChallengeSuccesses: 0
        )
        var requestedFormatIDs: [String] = []
        let service = YouTubeAudioImportService(
            extract: { _ in result },
            download: { request in
                let path = try XCTUnwrap(request.url?.lastPathComponent)
                requestedFormatIDs.append(path)
                let status = path == "preferred" ? 403 : 200
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil)!
                return (status == 403 ? rejectedDownload : acceptedDownload, response)
            },
            importFile: { _ in TrackImportReport(imported: [Track(title: "Title", audioFilename: "title.m4a")]) }
        )

        let outcome = try await service.run(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")), update: { _ in })

        XCTAssertEqual(requestedFormatIDs, ["preferred", "fallback"])
        XCTAssertEqual(outcome.extraction.format.formatID, "fallback")
    }

    @MainActor
    func testProductionErrorMessagesGiveRuntimeRecoveryAndValidationGuidance() {
        XCTAssertTrue(YouTubeDownloadController.userMessage(for: YouTubeImportError.runtimeBusy).contains("Wait"))
        XCTAssertTrue(YouTubeDownloadController.userMessage(for: YouTubeImportError.runtimeUnavailable).contains("restart"))
        XCTAssertTrue(YouTubeDownloadController.userMessage(for: YouTubeImportError.runtimeTimedOut).contains("restart"))
        XCTAssertTrue(YouTubeDownloadController.userMessage(for: YouTubeImportError.noCompatibleAudio).contains("another video"))
        XCTAssertEqual(YouTubeDownloadController.userMessage(for: URLError(.cancelled)), "Download cancelled.")
        XCTAssertTrue(YouTubeDownloadController.userMessage(for: URLError(.notConnectedToInternet)).contains("could not reach YouTube"))
        XCTAssertTrue(YouTubeDownloadController.userMessage(for: URLError(.timedOut)).contains("timed out"))
        XCTAssertTrue(YouTubeDownloadController.userMessage(for: YouTubeImportError.extraction("private extractor detail")).contains("public"))
        XCTAssertFalse(YouTubeDownloadController.userMessage(for: YouTubeImportError.downloadFailed).contains("Check your connection"))
        XCTAssertTrue(YouTubeDownloadController.userMessage(for: YouTubeImportError.httpFailure(403)).contains("HTTP 403"))
    }

    @MainActor
    func testExplicitPlayReportsSafeFailureWithoutRemovingSavedTrack() {
        let track = Track(title: "Saved", audioFilename: "saved.m4a")
        let engine = YouTubeTestPlayback()
        engine.failNextLoad = true
        let playback = PlaybackController(engine: engine, tracks: [track])
        let controller = YouTubeDownloadController(playback: playback) { _, _ in
            XCTFail("Playback test must not start a download.")
            throw CancellationError()
        }
        controller.play(track)

        XCTAssertNotNil(playback.currentTrack)
        XCTAssertEqual(playback.currentTrack?.id, track.id)
        XCTAssertEqual(controller.playbackMessage, "The track is saved, but playback could not be started. Try again from your library.")
    }

    func testAcceptsOnlySupportedPublicSingleVideoURLs() {
        XCTAssertEqual(YouTubeVideoURL("https://www.youtube.com/watch?v=abcdefghijk")?.videoID, "abcdefghijk")
        XCTAssertEqual(YouTubeVideoURL("https://youtu.be/abcdefghijk?t=10")?.videoID, "abcdefghijk")
        XCTAssertEqual(YouTubeVideoURL("https://m.youtube.com/watch?v=abcdefghijk")?.videoID, "abcdefghijk")

        XCTAssertNil(YouTubeVideoURL("http://www.youtube.com/watch?v=abcdefghijk"))
        XCTAssertNil(YouTubeVideoURL("https://youtube.com.evil.test/watch?v=abcdefghijk"))
        XCTAssertNil(YouTubeVideoURL("https://youtube.com/watch?v=abcdefghijk&list=PL123"))
        XCTAssertNil(YouTubeVideoURL("https://youtu.be/abcdefghijk?list=PL123"))
        XCTAssertNil(YouTubeVideoURL("https://www.youtube.com/playlist?list=PL123"))
        XCTAssertNil(YouTubeVideoURL("https://www.youtube.com/shorts/abcdefghijk"))
        XCTAssertNil(YouTubeVideoURL("https://user@youtube.com/watch?v=abcdefghijk"))
        XCTAssertNil(YouTubeVideoURL("https://www.youtube.com/watch?v=short"))
    }

    func testPreservesYtDlpFormatRankingAndRejectsIncompatibleFormats() throws {
        let formats = [
            format("webm", extension: "webm", protocol: "https", audio: "opus", video: "none", bitrate: 256),
            format("video", extension: "mp4", protocol: "https", audio: "mp4a.40.2", video: "avc1.4d401f", bitrate: 900),
            format("manifest", extension: "m4a", protocol: "m3u8_native", audio: "mp4a.40.2", video: "none", bitrate: 256),
            format("insecure", extension: "m4a", protocol: "https", audio: "mp4a.40.2", video: "none", bitrate: 320, scheme: "http"),
            format("aac-high-bitrate", extension: "m4a", protocol: "https", audio: "mp4a.40.2", video: "none", bitrate: 256),
            format("yt-dlp-preferred", extension: "m4a", protocol: "https", audio: "mp4a.40.2", video: "none", bitrate: 128)
        ]

        XCTAssertEqual(YouTubeAudioFormat.best(from: formats)?.formatID, "yt-dlp-preferred")
        XCTAssertNil(YouTubeAudioFormat.best(from: Array(formats.prefix(4))))
    }

    func testExtractionMetadataSkipsFormatsWithMissingOptionalFields() throws {
        let json = #"{"id":"abcdefghijk","title":"Example","isLive":false,"formats":[{"formatID":"image","extension":"jpg","protocol":"https","audioCodec":null,"videoCodec":null,"url":"https://cdn.example.test/image"},{"formatID":"audio","extension":"m4a","protocol":"https","audioCodec":"mp4a.40.2","videoCodec":"none","url":"https://cdn.example.test/audio","httpHeaders":{},"bitrate":128,"source_preference":2,"preference":1}],"webkitJSCChallengeCalls":1,"webkitJSCChallengeSuccesses":1}"#
        let extraction = try JSONDecoder().decode(YouTubeExtraction.self, from: Data(json.utf8))
        let formats = extraction.formats.compactMap(\.directAudioFormat)

        XCTAssertEqual(formats.map(\.formatID), ["audio"])
        XCTAssertEqual(YouTubeAudioFormat.best(from: formats)?.formatID, "audio")
        XCTAssertEqual(formats.first?.sourcePreference, 2)
        XCTAssertEqual(formats.first?.preference, 1)
    }

    func testExpiredSignedURLGetsExactlyOneFreshExtraction() {
        XCTAssertTrue(YouTubeSignedURLRetryPolicy.shouldReextract(statusCode: 401, attempt: 0))
        XCTAssertTrue(YouTubeSignedURLRetryPolicy.shouldReextract(statusCode: 403, attempt: 0))
        XCTAssertFalse(YouTubeSignedURLRetryPolicy.shouldReextract(statusCode: 403, attempt: 1))
        XCTAssertFalse(YouTubeSignedURLRetryPolicy.shouldReextract(statusCode: 404, attempt: 0))
        XCTAssertFalse(YouTubeSignedURLRetryPolicy.shouldReextract(statusCode: 500, attempt: 0))
    }

    func testM4AContainerProbeRequiresAnFTYPBoxHeader() {
        XCTAssertTrue(YouTubeAudioContainer.hasM4AFileType(Data([0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70])))
        XCTAssertFalse(YouTubeAudioContainer.hasM4AFileType(Data([0, 0, 0, 24, 0x6D, 0x6F, 0x6F, 0x76])))
        XCTAssertFalse(YouTubeAudioContainer.hasM4AFileType(Data([0, 0, 0, 4])))
    }

    func testTemporaryFileScopeRemovesURLSessionFilesWhenValidationOrMoveFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vipod-youtube-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let downloaded = root.appendingPathComponent("urlsession-download.tmp")
        let invalidContainer = Data("not an audio container".utf8)
        XCTAssertFalse(YouTubeAudioContainer.hasM4AFileType(invalidContainer))
        try invalidContainer.write(to: downloaded)
        var scope = YouTubeTemporaryFileScope()
        scope.track(root)
        scope.track(downloaded)

        XCTAssertThrowsError(try scope.move(downloaded, to: root.appendingPathComponent("missing/title.m4a")))
        scope.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.path), "The download stays owned until a successful move and is deleted on failure.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), "The per-job directory is removed on every exit path.")
    }

    func testTemporaryFileScopeCleansDownloadedAndRenamedFilesAfterFailures() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let downloaded = root.appendingPathComponent("urlsession-download.tmp")
        try Data("payload".utf8).write(to: downloaded)
        var scope = YouTubeTemporaryFileScope()
        scope.track(downloaded)
        XCTAssertThrowsError(try scope.move(downloaded, to: root.appendingPathComponent("missing/title.m4a")))
        scope.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.path), "A failed move must leave the source registered for cleanup.")

        let secondDownload = root.appendingPathComponent("refreshed-download.tmp")
        try Data("payload".utf8).write(to: secondDownload)
        let jobDirectory = root.appendingPathComponent("job", isDirectory: true)
        try FileManager.default.createDirectory(at: jobDirectory, withIntermediateDirectories: false)
        let titleDerivedFile = jobDirectory.appendingPathComponent("Example Title.m4a")
        scope.track(secondDownload)
        scope.track(jobDirectory)
        try scope.move(secondDownload, to: titleDerivedFile)

        scope.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: titleDerivedFile.path), "Cancellation or validation failure must remove the title-derived temporary audio.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: jobDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDownload.path))
    }

    private func format(
        _ id: String,
        extension ext: String,
        protocol protocolName: String,
        audio: String,
        video: String,
        bitrate: Double,
        scheme: String = "https",
        urlPath: String = "audio"
    ) -> YouTubeAudioFormat {
        YouTubeAudioFormat(
            formatID: id,
            extensionName: ext,
            protocolName: protocolName,
            audioCodec: audio,
            videoCodec: video,
            url: URL(string: "\(scheme)://cdn.example.test/\(urlPath)")!,
            httpHeaders: [:],
            filesize: nil,
            bitrate: bitrate
        )
    }

    private func extractionResult(_ title: String) -> YouTubeExtractionResult {
        let format = format("audio", extension: "m4a", protocol: "https", audio: "mp4a.40.2", video: "none", bitrate: 128)
        return YouTubeExtractionResult(
            id: "abcdefghijk",
            title: title,
            format: format,
            formats: [format],
            webkitJSCChallengeCalls: 0,
            webkitJSCChallengeSuccesses: 0
        )
    }
}

@MainActor
private final class YouTubeTestPlayback: AudioPlayback {
    nonisolated deinit {}
    private(set) var status: AudioPlaybackStatus = .idle
    var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var onEvent: (@MainActor @Sendable (AudioPlaybackEvent) -> Void)?
    var onStateChange: (@MainActor @Sendable () -> Void)?
    var failNextLoad = false

    func load(_ track: Track) throws {
        if failNextLoad { failNextLoad = false; throw PlaybackError.noTrackLoaded }
        duration = 20
        status = .ready
        onStateChange?()
    }
    func play() throws { status = .playing; onStateChange?() }
    func pause() { status = .paused; onStateChange?() }
    func seek(to seconds: TimeInterval) throws { elapsed = seconds; onStateChange?() }
    func stop() { status = .idle; elapsed = 0; onStateChange?() }
}
