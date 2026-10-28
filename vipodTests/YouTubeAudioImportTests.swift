import XCTest
import UniformTypeIdentifiers
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
    func testProductionControllerRequiresAnalyzePreviewThenExplicitDownloadAndRetainsReceipt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-controller-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let downloaded = root.appendingPathComponent("download.m4a")
        try Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]).write(to: downloaded)
        var extractionCount = 0
        var downloadCount = 0
        let settled = [expectation(description: "analysis settled"), expectation(description: "download settled")]
        var settledCount = 0
        let service = YouTubeAudioImportService(
            extract: { _ in extractionCount += 1; return self.extractionResult("Preview title") },
            download: { request in
                downloadCount += 1
                return (downloaded, HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            importFile: { _ in TrackImportReport(imported: [Track(title: "Preview title", audioFilename: "saved.m4a")]) }
        )
        let controller = YouTubeDownloadController(onJobSettled: {
            settled[settledCount].fulfill()
            settledCount += 1
        }, service: service)
        controller.urlText = "https://youtu.be/abcdefghijk"

        controller.submit()
        await fulfillment(of: [settled[0]], timeout: 5)
        guard case .previewReady(let preview) = controller.state else { return XCTFail("Analysis should stop at a preview.") }
        XCTAssertEqual(preview.effectiveMetadata.title, "Preview title")
        XCTAssertEqual(extractionCount, 1)
        XCTAssertEqual(downloadCount, 0, "Analysis must never transfer media.")

        controller.downloadPreview()
        await fulfillment(of: [settled[1]], timeout: 5)
        XCTAssertEqual(downloadCount, 1)
        XCTAssertEqual(extractionCount, 1, "First download reuses its prepared extraction.")
        XCTAssertEqual(controller.savedTrackReceipt?.title, "Preview title")
        XCTAssertEqual(controller.urlText, "")

        controller.urlText = "https://youtu.be/zzzzzzzzzzz"
        XCTAssertFalse(controller.previewExists)
        guard case .ready = controller.state else { return XCTFail("Changing the link invalidates the previous preview.") }
        XCTAssertEqual(controller.savedTrackReceipt?.title, "Preview title", "Receipt remains available while the next link is prepared.")
    }

    @MainActor
    func testPreparedDownloadPassesConfirmedMetadataAndArtworkOverrideToTagger() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-confirmed-tags-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let downloaded = root.appendingPathComponent("download.m4a")
        try Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]).write(to: downloaded)
        var receivedMetadata: YouTubeEffectiveMetadata?
        var receivedArtwork: Data?
        var importedFile: URL?
        var importedSignature: Data?
        let service = YouTubeAudioImportService(
            extract: { _ in self.extractionResult("Source title") },
            download: { request in
                let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
                return (downloaded, response)
            },
            importFile: { url in
                importedFile = url
                importedSignature = (try? Data(contentsOf: url)).map { Data($0.prefix(8)) }
                return TrackImportReport(imported: [Track(title: "Confirmed title", audioFilename: "confirmed.m4a")])
            },
            tag: { source, metadata, artwork in
                receivedMetadata = metadata
                receivedArtwork = artwork
                return source
            },
            artwork: { _ in XCTFail("A MusicBrainz artwork override must not be replaced by a YouTube thumbnail fetch."); throw YouTubeImportError.artworkUnavailable },
            passthroughAAC: { _ in true }
        )
        let prepared = try await service.analyze(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")))
        let confirmed = YouTubeEffectiveMetadata(
            title: "Confirmed title", videoTitle: "Source title", artist: "Confirmed artist",
            album: "Confirmed album", albumArtist: "Confirmed album artist", releaseDate: "2025-04-03",
            genre: "Jazz", trackNumber: 4, discNumber: 2, trackNumberTotal: 12, discNumberTotal: 2
        )
        let cover = Data("selected musicbrainz cover".utf8)

        let outcome = try await service.download(
            prepared, metadata: confirmed, artworkOverride: cover, update: { _ in }
        )

        XCTAssertEqual(receivedMetadata, confirmed)
        XCTAssertEqual(receivedArtwork, cover)
        XCTAssertEqual(outcome.track.title, "Confirmed title")
        XCTAssertNotNil(importedFile)
        XCTAssertEqual(importedSignature, Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]))
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
    func testPreparedDownloadSkipsAACSubtypeThatCannotPassThroughAndReportsWinningFormat() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-aac-subtype-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let heSource = root.appendingPathComponent("he-response.tmp")
        let lcSource = root.appendingPathComponent("lc-response.tmp")
        for url in [heSource, lcSource] {
            try Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]).write(to: url)
        }
        let heFormat = format("he-aac", extension: "m4a", protocol: "https", audio: "mp4a.40.5", video: "none", bitrate: 128, urlPath: "he-aac")
        let lcFormat = format("aac-lc", extension: "m4a", protocol: "https", audio: "mp4a.40.2", video: "none", bitrate: 96, urlPath: "aac-lc")
        let extraction = YouTubeExtractionResult(
            id: "abcdefghijk", title: "Video", format: lcFormat, formats: [heFormat, lcFormat],
            webkitJSCChallengeCalls: 0, webkitJSCChallengeSuccesses: 0
        )
        var requested: [String] = []
        var preflighted: [URL] = []
        var importedURL: URL?
        let service = YouTubeAudioImportService(
            extract: { _ in extraction },
            download: { request in
                let id = try XCTUnwrap(request.url?.lastPathComponent)
                requested.append(id)
                let source = id == "he-aac" ? heSource : lcSource
                return (source, HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            importFile: { url in
                importedURL = url
                return TrackImportReport(imported: [Track(title: "Video", audioFilename: "saved.m4a")])
            },
            tag: { source, _, artwork in
                XCTAssertNil(artwork)
                return source
            },
            passthroughAAC: { url in
                preflighted.append(url)
                return preflighted.count > 1
            }
        )

        let prepared = try await service.analyze(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")))
        let outcome = try await service.download(prepared, update: { _ in })

        XCTAssertEqual(requested, ["he-aac", "aac-lc"])
        XCTAssertEqual(outcome.extraction.format.formatID, "aac-lc")
        XCTAssertEqual(preflighted.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preflighted[0].path), "Rejected codec source is deleted before trying the next ranked rendition.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(importedURL).path), "The accepted tagged temporary is cleaned after import.")
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

    func testNativePayloadDecodesOptionalPreviewAndSeparatesExactAndApproximateSize() throws {
        let json = #"{"id":"abcdefghijk","title":"Example","isLive":false,"duration":90.5,"thumbnail":"https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg","channel":"Source Channel","uploadDate":"20261008","music":{"title":"Song","artist":"Artist","date":"2024-05-03","trackNumber":"2/10"},"formats":[{"formatID":"audio","extension":"m4a","protocol":"https","audioCodec":"mp4a.40.2","videoCodec":"none","url":"https://cdn.example.test/audio","filesize":1234,"filesize_approx":1400}],"webkitJSCChallengeCalls":0,"webkitJSCChallengeSuccesses":0}"#
        let extraction = try JSONDecoder().decode(YouTubeExtraction.self, from: Data(json.utf8))
        let format = try XCTUnwrap(extraction.formats.first?.directAudioFormat)

        XCTAssertEqual(extraction.duration, 90.5)
        XCTAssertEqual(extraction.channel, "Source Channel")
        XCTAssertEqual(extraction.music?.title, "Song")
        XCTAssertEqual(extraction.music?.trackNumber, "2/10")
        XCTAssertEqual(format.filesize, 1234)
        XCTAssertEqual(format.filesizeApprox, 1400)
    }

    @MainActor
    func testAnalysisBuildsURLFreeEffectivePreviewWithoutDownloadingOrImporting() async throws {
        let result = extractionResult("Video title", music: YouTubeMusicMetadata(
            title: "Track title", artist: "Artist", album: "Album", albumArtist: "Band",
            date: "2024-03", genre: "Jazz", trackNumber: "7/12", discNumber: "2/3"
        ), duration: 91.5, channel: "Uploader", uploadDate: "20261008")
        var downloadCalled = false
        var importCalled = false
        let service = YouTubeAudioImportService(
            extract: { _ in result },
            download: { _ in downloadCalled = true; throw CancellationError() },
            importFile: { _ in importCalled = true; return nil }
        )

        let prepared = try await service.analyze(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")))

        XCTAssertEqual(prepared.preview.videoTitle, "Video title")
        XCTAssertEqual(prepared.preview.channel, "Uploader")
        XCTAssertEqual(prepared.preview.uploadDate, "20261008")
        XCTAssertEqual(prepared.preview.duration, 91.5)
        XCTAssertEqual(prepared.preview.effectiveMetadata.title, "Track title")
        XCTAssertEqual(prepared.preview.effectiveMetadata.releaseDate, "2024-03")
        XCTAssertEqual(prepared.preview.effectiveMetadata.trackNumber, 7)
        XCTAssertEqual(prepared.preview.effectiveMetadata.trackNumberTotal, 12)
        XCTAssertEqual(prepared.preview.effectiveMetadata.discNumber, 2)
        XCTAssertEqual(prepared.preview.effectiveMetadata.discNumberTotal, 3)
        XCTAssertFalse(downloadCalled)
        XCTAssertFalse(importCalled)
    }

    @MainActor
    func testExtensionlessURLSessionDownloadIsRenamedToM4ABeforeTagging() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-extensionless-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let downloaded = root.appendingPathComponent(UUID().uuidString)
        let tagged = root.appendingPathComponent("tagged.m4a")
        try Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]).write(to: downloaded)
        try Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]).write(to: tagged)
        var taggedSourceExtension: String?
        let service = YouTubeAudioImportService(
            extract: { _ in self.extractionResult("Extensionless") },
            download: { request in
                (downloaded, HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            importFile: { _ in TrackImportReport(imported: [Track(title: "Extensionless", audioFilename: "extensionless.m4a")]) },
            tag: { source, _, _ in
                taggedSourceExtension = source.pathExtension
                return tagged
            }
        )

        _ = try await service.run(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")), update: { _ in })

        XCTAssertEqual(taggedSourceExtension, "m4a", "URLSession temporary downloads have no reliable filename extension.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.path), "The original URLSession temporary should be moved into managed cleanup scope.")
    }

    @MainActor
    func testPreparedDownloadReusesFirstExtractionAndPreservesMetadataThroughFreshURLFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-prepared-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstDownload = root.appendingPathComponent("expired.tmp")
        let secondDownload = root.appendingPathComponent("fresh.tmp")
        try Data("expired".utf8).write(to: firstDownload)
        try Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]).write(to: secondDownload)
        let originalMusic = YouTubeMusicMetadata(title: "Confirmed title", artist: "Confirmed artist", album: nil, albumArtist: nil, date: "2024", genre: nil, trackNumber: "3/9", discNumber: nil)
        let oldFormat = format("old", extension: "m4a", protocol: "https", audio: "mp4a.40.2", video: "none", bitrate: 128, urlPath: "expired")
        let first = YouTubeExtractionResult(id: "abcdefghijk", title: "Video title", format: oldFormat, formats: [oldFormat], webkitJSCChallengeCalls: 0, webkitJSCChallengeSuccesses: 0, music: originalMusic)
        let freshFormat = format("fresh", extension: "m4a", protocol: "https", audio: "mp4a.40.2", video: "none", bitrate: 96, urlPath: "fresh")
        let refreshed = YouTubeExtractionResult(id: "abcdefghijk", title: "Changed video title", format: freshFormat, formats: [freshFormat], webkitJSCChallengeCalls: 0, webkitJSCChallengeSuccesses: 0, music: YouTubeMusicMetadata(title: "Unconfirmed refresh title", artist: "Other", album: nil, albumArtist: nil, date: nil, genre: nil, trackNumber: nil, discNumber: nil))
        var extractionCount = 0
        var requestIDs: [String] = []
        var tagSnapshot: YouTubeEffectiveMetadata?
        var importedURL: URL?
        let service = YouTubeAudioImportService(
            extract: { _ in extractionCount += 1; return extractionCount == 1 ? first : refreshed },
            download: { request in
                let id = try XCTUnwrap(request.url?.lastPathComponent)
                requestIDs.append(id)
                let status = id == "expired" ? 403 : 200
                return (status == 403 ? firstDownload : secondDownload, HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil)!)
            },
            importFile: { url in
                importedURL = url
                return TrackImportReport(imported: [Track(title: "Confirmed title", artist: "Confirmed artist", audioFilename: "saved.m4a")])
            },
            tag: { source, metadata, artwork in
                tagSnapshot = metadata
                XCTAssertNil(artwork)
                return source
            }
        )
        let prepared = try await service.analyze(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")))
        let progressOperationID = prepared.operationID
        var events: [YouTubeAudioImportService.DownloadProgress] = []
        let outcome = try await service.download(prepared, update: { _ in }, progress: { events.append($0) })

        XCTAssertEqual(extractionCount, 2, "One analysis plus exactly one refresh; no redundant extraction before the first request.")
        XCTAssertEqual(requestIDs, ["expired", "fresh"])
        XCTAssertEqual(tagSnapshot?.title, "Confirmed title")
        XCTAssertEqual(tagSnapshot?.artist, "Confirmed artist")
        XCTAssertEqual(tagSnapshot?.trackNumber, 3)
        XCTAssertEqual(tagSnapshot?.trackNumberTotal, 9)
        XCTAssertEqual(outcome.extraction.format.formatID, "fresh", "Receipt reports actual selected format.")
        XCTAssertEqual(outcome.extraction.title, "Video title", "Refresh metadata does not replace confirmed preview values.")
        XCTAssertEqual(outcome.extraction.music?.title, "Confirmed title")
        XCTAssertEqual(events.map(\.attempt), [0, 0, 1, 1], "Each new media attempt publishes a fresh zero-byte progress value.")
        XCTAssertTrue(events.allSatisfy { $0.operationID == progressOperationID })
        XCTAssertTrue(events.allSatisfy { $0.fractionCompleted == nil }, "Unknown response lengths remain indeterminate.")
        XCTAssertNotNil(importedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(importedURL).path), "Service-owned tagged temporary is removed after import returns.")
    }

    @MainActor
    func testTagVerificationFailureNeverImportsAndCleansTheDownloadedSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-tag-failure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let downloaded = root.appendingPathComponent("download.m4a")
        try Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]).write(to: downloaded)
        var importCalled = false
        let service = YouTubeAudioImportService(
            extract: { _ in self.extractionResult("Video") },
            download: { request in (downloaded, HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!) },
            importFile: { _ in importCalled = true; return nil },
            tag: { _, _, _ in throw YouTubeImportError.metadataVerificationFailed }
        )

        do {
            _ = try await service.run(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")), update: { _ in })
            XCTFail("Tag readback failure must stop before import.")
        } catch let error as YouTubeImportError {
            guard case .metadataVerificationFailed = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertFalse(importCalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.path))
    }

    @MainActor
    func testPreparedDownloadKeepsCommittedLibraryTrackWhenCancellationArrivesDuringCommit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-prepared-late-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let downloaded = root.appendingPathComponent("download-without-extension")
        try Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]).write(to: downloaded)
        let savedTrack = Track(title: "Committed", audioFilename: "committed.m4a")
        var operation: Task<YouTubeAudioImportOutcome, Error>?
        var importedURL: URL?
        let service = YouTubeAudioImportService(
            extract: { _ in self.extractionResult("Confirmed") },
            download: { request in
                (downloaded, HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            importFile: { url in
                importedURL = url
                operation?.cancel()
                return TrackImportReport(imported: [savedTrack])
            },
            tag: { source, _, _ in source }
        )
        let prepared = try await service.analyze(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")))
        operation = Task { try await service.download(prepared, update: { _ in }) }

        let outcome = try await XCTUnwrap(operation).value

        XCTAssertEqual(outcome.track, savedTrack)
        XCTAssertTrue(outcome.cancellationArrivedAfterCommit)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(importedURL).path), "The committed track survives; the service-owned tagged temporary is still cleaned.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.path))
    }

    @MainActor
    func testThumbnailFailureIsNonfatalAndReturnedAsAnExplicitWarning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-artwork-warning-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let downloaded = root.appendingPathComponent("download.m4a")
        try Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]).write(to: downloaded)
        var imported = false
        let service = YouTubeAudioImportService(
            extract: { _ in self.extractionResult("Video", music: nil, thumbnail: URL(string: "https://i.ytimg.com/cover.jpg")) },
            download: { request in (downloaded, HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!) },
            importFile: { _ in imported = true; return TrackImportReport(imported: [Track(title: "Video", audioFilename: "saved.m4a")]) },
            artwork: { _ in throw YouTubeImportError.artworkUnavailable }
        )

        let outcome = try await service.run(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")), update: { _ in })

        XCTAssertTrue(imported)
        XCTAssertEqual(outcome.artworkWarning, "Artwork could not be downloaded; the audio will be saved without artwork.")
    }

    @MainActor
    func testKnownDownloadLengthProducesClampedProgress() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-known-progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let downloaded = root.appendingPathComponent("download.m4a")
        try Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]).write(to: downloaded)
        let mediaFormat = YouTubeAudioFormat(formatID: "audio", extensionName: "m4a", protocolName: "https", audioCodec: "mp4a.40.2", videoCodec: "none", url: URL(string: "https://cdn.example.test/audio")!, httpHeaders: [:], filesize: 10, bitrate: 128)
        let extraction = YouTubeExtractionResult(id: "abcdefghijk", title: "Song", format: mediaFormat, formats: [mediaFormat], webkitJSCChallengeCalls: 0, webkitJSCChallengeSuccesses: 0)
        let service = YouTubeAudioImportService(
            extract: { _ in extraction },
            download: { request in (downloaded, HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": "10"])!) },
            importFile: { _ in TrackImportReport(imported: [Track(title: "Song", audioFilename: "song.m4a")]) }
        )
        var progress: [YouTubeAudioImportService.DownloadProgress] = []

        let prepared = try await service.analyze(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")))
        _ = try await service.download(prepared, update: { _ in }, progress: { progress.append($0) })

        XCTAssertEqual(progress.map(\.completedBytes), [0, 10])
        XCTAssertEqual(progress.map(\.fractionCompleted), [0, 1])
        XCTAssertEqual(progress.map(\.expectedBytes), [10, 10])
    }

    @MainActor
    func testCancellationAfterTransferReturnsCleansSourceBeforeImport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-cancel-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let downloaded = root.appendingPathComponent("download.m4a")
        try Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]).write(to: downloaded)
        let transferStarted = expectation(description: "transfer started")
        var continuation: CheckedContinuation<(URL, URLResponse), Error>?
        var imported = false
        let service = YouTubeAudioImportService(
            extract: { _ in self.extractionResult("Song") },
            download: { _ in
                transferStarted.fulfill()
                return try await withCheckedThrowingContinuation { continuation = $0 }
            },
            importFile: { _ in imported = true; return nil }
        )
        let task = Task { try await service.run(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")), update: { _ in }) }
        await fulfillment(of: [transferStarted], timeout: 5)
        task.cancel()
        let request = URLRequest(url: URL(string: "https://cdn.example.test/audio")!)
        continuation?.resume(returning: (downloaded, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }

        XCTAssertFalse(imported)
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.path))
    }

    @MainActor
    func testPreparedPipelineTagsRealAACThenImportsTaggedFileThroughLibrary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-end-to-end-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledFixture = try XCTUnwrap(Bundle(for: FileTrackRepositoryTests.self).url(forResource: "VIPOD-ArtworkTone", withExtension: "m4a"))
        let downloaded = root.appendingPathComponent("transfer.m4a")
        try FileManager.default.copyItem(at: bundledFixture, to: downloaded)
        let library = try FileTrackRepository(storageURL: root.appendingPathComponent("library", isDirectory: true))
        let thumbnailArtwork = try jpegArtworkFixture()
        let extraction = extractionResult(
            "Video title",
            music: YouTubeMusicMetadata(title: "Prepared title", artist: "Prepared artist", album: "Prepared album", albumArtist: "Prepared band", date: "2024", genre: "Jazz", trackNumber: "4/10", discNumber: "1/2"),
            thumbnail: URL(string: "https://i.ytimg.com/vi/abcdefghijk/maxresdefault.jpg")
        )
        let service = YouTubeAudioImportService(
            extract: { _ in extraction },
            download: { request in (downloaded, HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!) },
            importFile: { try? await library.importTracks(from: [$0]) },
            tag: { source, metadata, artwork in try await YouTubeM4AMetadataWriter().write(sourceURL: source, metadata: metadata, artwork: artwork, temporaryDirectory: root) },
            artwork: { _ in thumbnailArtwork }
        )

        let prepared = try await service.analyze(try XCTUnwrap(YouTubeVideoURL("https://youtu.be/abcdefghijk")))
        let outcome = try await service.download(prepared, update: { _ in })
        let persisted = try await FileTrackRepository(storageURL: root.appendingPathComponent("library", isDirectory: true)).tracks()

        XCTAssertEqual(outcome.track.title, "Prepared title")
        XCTAssertEqual(outcome.track.artist, "Prepared artist")
        XCTAssertEqual(outcome.track.album, "Prepared album")
        XCTAssertEqual(outcome.track.albumArtist, "Prepared band")
        XCTAssertEqual(outcome.track.trackNumber, 4)
        XCTAssertEqual(outcome.track.discNumber, 1)
        let importedArtwork = try await library.artworkData(for: outcome.track)
        XCTAssertEqual(importedArtwork, thumbnailArtwork)
        XCTAssertEqual(persisted, [outcome.track])
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
        extractionResult(title, music: nil)
    }

    private func extractionResult(
        _ title: String,
        music: YouTubeMusicMetadata?,
        duration: Double? = nil,
        channel: String? = nil,
        uploadDate: String? = nil,
        thumbnail: URL? = nil
    ) -> YouTubeExtractionResult {
        let format = format("audio", extension: "m4a", protocol: "https", audio: "mp4a.40.2", video: "none", bitrate: 128)
        return YouTubeExtractionResult(
            id: "abcdefghijk",
            title: title,
            format: format,
            formats: [format],
            webkitJSCChallengeCalls: 0,
            webkitJSCChallengeSuccesses: 0,
            duration: duration,
            thumbnail: thumbnail,
            channel: channel,
            uploadDate: uploadDate,
            music: music
        )
    }

    private func jpegArtworkFixture() throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil),
              let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return output as Data
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
