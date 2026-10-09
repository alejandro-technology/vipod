import Foundation
import Observation
#if DEBUG && os(iOS)
import AVFoundation
#endif

#if os(iOS)
@MainActor @Observable
final class YouTubeDownloadController {
    struct SavedReceipt: Equatable {
        let track: Track
        let format: String
        let bitrate: Double?
        let exactBytes: Int64?
        let approximateBytes: Int64?
    }
    enum State: Equatable {
        case ready
        case working(String)
        case cancelling
        case cancelled
        case failed(String)
        case completed(Track, cancellationArrivedAfterCommit: Bool)
        case previewReady(YouTubeVideoPreview)
    }

    private(set) var state: State = .ready
    private(set) var playbackMessage: String?
    private(set) var savedTrackReceipt: Track?
    private(set) var savedReceipt: SavedReceipt?
    private(set) var receiptCancellationArrivedAfterCommit = false
    var urlText = "" {
        didSet {
            guard urlText != oldValue, !clearingURLAfterSave else { return }
            preparedDownload = nil
            transferProgress = nil
            if case .working = state { return }
            if case .cancelling = state { return }
            state = .ready
        }
    }

    private let legacyDownload: (@MainActor (YouTubeVideoURL, @escaping @MainActor (YouTubeAudioImportService.Stage) -> Void) async throws -> YouTubeAudioImportOutcome)?
    private let analyze: (@MainActor (YouTubeVideoURL) async throws -> YouTubePreparedDownload)?
    private let preparedDownloadAction: (@MainActor (YouTubePreparedDownload, @escaping @MainActor (YouTubeAudioImportService.Stage) -> Void, @escaping @MainActor (YouTubeAudioImportService.DownloadProgress) -> Void) async throws -> YouTubeAudioImportOutcome)?
    private let playback: PlaybackController?
    private let onJobSettled: @MainActor () -> Void
    private var job: Task<Void, Never>?
    private var activeJobID: UUID?
    private var cancellationRequested = false
    private var preparedDownload: YouTubePreparedDownload?
    private var clearingURLAfterSave = false
    private var activeTransferAttempt = -1
    private(set) var transferProgress: YouTubeAudioImportService.DownloadProgress?
    private(set) var artworkWarning: String?
    #if DEBUG
    private var fixtureDriver: YouTubeDownloadUITestFixture?
    var fixtureStage: String? { fixtureDriver?.stage.rawValue }
    var fixtureCanAdvance: Bool { fixtureDriver?.canAdvance ?? false }

    init(playback: PlaybackController?, fixtureDriver: YouTubeDownloadUITestFixture) {
        self.playback = playback
        self.onJobSettled = {}
        self.legacyDownload = nil
        self.analyze = { video in
            let format = YouTubeAudioFormat(formatID: "fixture", extensionName: "m4a", protocolName: "https", audioCodec: "mp4a.40.2", videoCodec: "none", url: URL(string: "https://fixture.invalid/not-requested")!, httpHeaders: [:], filesize: 4_000, bitrate: 128)
            let extraction = YouTubeExtractionResult(id: video.videoID, title: "Fixture Video", format: format, formats: [format], webkitJSCChallengeCalls: 0, webkitJSCChallengeSuccesses: 0, duration: 93, thumbnail: nil, channel: "Fixture Channel", uploadDate: nil, music: YouTubeMusicMetadata(title: YouTubeDownloadUITestFixture.receiptTrackTitle, artist: "Fixture Artist", album: "Fixture Album", albumArtist: nil, date: nil, genre: nil, trackNumber: nil, discNumber: nil))
            let preview = YouTubeVideoPreview(videoID: video.videoID, videoTitle: extraction.title, duration: extraction.duration, thumbnailURL: nil, channel: extraction.channel, uploadDate: nil, effectiveMetadata: YouTubeEffectiveMetadata(title: YouTubeDownloadUITestFixture.receiptTrackTitle, videoTitle: extraction.title, artist: "Fixture Artist", album: "Fixture Album", albumArtist: nil, releaseDate: nil, genre: nil, trackNumber: nil, discNumber: nil, trackNumberTotal: nil, discNumberTotal: nil), formats: [YouTubePreviewFormat(formatID: "fixture", bitrate: 128, filesize: 4_000, filesizeApprox: nil)])
            return YouTubePreparedDownload(preview: preview, operationID: UUID(), extractedAt: Date(), extraction: extraction)
        }
        self.fixtureDriver = fixtureDriver
        self.preparedDownloadAction = { prepared, update, progress in
            let driver = fixtureDriver
            update(.downloading)
            progress(.init(operationID: prepared.operationID, attempt: 1, completedBytes: 1_000, expectedBytes: 4_000))
            try await driver.waitAtCurrentGate()
            progress(.init(operationID: prepared.operationID, attempt: 2, completedBytes: 400, expectedBytes: nil))
            try await driver.waitAtCurrentGate()
            progress(.init(operationID: prepared.operationID, attempt: 2, completedBytes: 4_000, expectedBytes: 4_000))
            update(.tagging)
            try await driver.waitAtCurrentGate()
            update(.importing)
            try await driver.waitAtCurrentGate()
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("vipod-youtube-ui-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let wav = root.appendingPathComponent("fixture.wav")
            try await Self.writeFixtureWave(to: wav)
            let source = root.appendingPathComponent("fixture.m4a")
            try await Self.exportFixtureAAC(from: wav, to: source)
            let tagged = try await YouTubeM4AMetadataWriter().write(sourceURL: source, metadata: prepared.preview.effectiveMetadata, temporaryDirectory: root)
            let report = await driver.importFile(tagged)
            guard let track = report?.imported.first else { throw YouTubeImportError.libraryImportFailed("The deterministic UI fixture could not be saved.") }
            return YouTubeAudioImportOutcome(track: track, extraction: prepared.extraction, cancellationArrivedAfterCommit: false, artworkWarning: "No video thumbnail was available; the audio was saved without artwork.")
        }
    }

    func advanceFixture() {
        #if DEBUG
        fixtureDriver?.advance()
        #endif
    }

    func cancelFixtureOperation() {
        #if DEBUG
        fixtureDriver?.cancelOperation()
        #endif
    }

    #if DEBUG
    private static func writeFixtureWave(to url: URL) async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount: AVAudioFrameCount = 44_100
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount), let samples = buffer.floatChannelData?[0] else { throw CocoaError(.fileWriteUnknown) }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) { samples[frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44_100) * 0.08) }
        try file.write(from: buffer)
    }

    private static func exportFixtureAAC(from source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw CocoaError(.fileWriteUnknown) }
        exporter.outputURL = destination
        exporter.outputFileType = .m4a
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                if exporter.status == .completed { continuation.resume() }
                else { continuation.resume(throwing: exporter.error ?? CocoaError(.fileWriteUnknown)) }
            }
        }
    }
    #endif
    #endif

    init(
        playback: PlaybackController? = nil,
        onJobSettled: @escaping @MainActor () -> Void = {},
        download: @escaping @MainActor (YouTubeVideoURL, @escaping @MainActor (YouTubeAudioImportService.Stage) -> Void) async throws -> YouTubeAudioImportOutcome
    ) {
        self.playback = playback
        self.onJobSettled = onJobSettled
        self.legacyDownload = download
        self.analyze = nil
        self.preparedDownloadAction = nil
    }

    init(
        playback: PlaybackController? = nil,
        onJobSettled: @escaping @MainActor () -> Void = {},
        analyze: @escaping @MainActor (YouTubeVideoURL) async throws -> YouTubePreparedDownload,
        downloadPrepared: @escaping @MainActor (
            YouTubePreparedDownload,
            @escaping @MainActor (YouTubeAudioImportService.Stage) -> Void,
            @escaping @MainActor (YouTubeAudioImportService.DownloadProgress) -> Void
        ) async throws -> YouTubeAudioImportOutcome
    ) {
        self.playback = playback
        self.onJobSettled = onJobSettled
        self.legacyDownload = nil
        self.analyze = analyze
        self.preparedDownloadAction = downloadPrepared
    }

    init(playback: PlaybackController? = nil, onJobSettled: @escaping @MainActor () -> Void = {}, service: YouTubeAudioImportService) {
        self.playback = playback
        self.onJobSettled = onJobSettled
        self.legacyDownload = nil
        self.analyze = { try await service.analyze($0) }
        self.preparedDownloadAction = { prepared, update, progress in
            try await service.download(prepared, update: update, progress: progress)
        }
    }

    #if DEBUG
    init(
        onJobSettled: @escaping @MainActor () -> Void = {},
        analyze: @escaping @MainActor (YouTubeVideoURL) async throws -> YouTubePreparedDownload,
        downloadPrepared: @escaping @MainActor (YouTubePreparedDownload, @escaping @MainActor (YouTubeAudioImportService.Stage) -> Void, @escaping @MainActor (YouTubeAudioImportService.DownloadProgress) -> Void) async throws -> YouTubeAudioImportOutcome
    ) {
        self.playback = nil
        self.onJobSettled = onJobSettled
        self.legacyDownload = nil
        self.analyze = analyze
        self.preparedDownloadAction = downloadPrepared
    }
    #endif

    nonisolated deinit {}

    var isBusy: Bool { job != nil }
    var previewExists: Bool { preparedDownload != nil }
    var retainedPreview: YouTubeVideoPreview? { preparedDownload?.preview }
    var isPreviewReady: Bool { if case .previewReady = state { return true }; return false }

    func submit() {
        guard job == nil else { return }
        guard let video = YouTubeVideoURL(urlText) else {
            state = .failed("Enter a valid link to one public YouTube video.")
            return
        }

        let jobID = UUID()
        savedTrackReceipt = nil
        savedReceipt = nil
        receiptCancellationArrivedAfterCommit = false
        activeJobID = jobID
        cancellationRequested = false
        playbackMessage = nil
        artworkWarning = nil
        transferProgress = nil
        if let analyze, preparedDownloadAction != nil {
            startAnalysis(video, analyze: analyze, onJobSettled: onJobSettled)
            return
        }
        guard let legacyDownload else { return }
        state = .working("Extracting video information…")
        job = Task { [legacyDownload, onJobSettled] in
            defer {
                finish(jobID: jobID)
                onJobSettled()
            }
            do {
                let outcome = try await legacyDownload(video) { [weak self] stage in
                    guard let self, self.activeJobID == jobID, !self.cancellationRequested else { return }
                    self.state = .working(Self.progressMessage(for: stage))
                }
                // A durable repository result wins over a cancellation request that arrived
                // while the library was committing its catalog transaction.
                guard activeJobID == jobID else { return }
                state = .completed(outcome.track, cancellationArrivedAfterCommit: cancellationRequested || outcome.cancellationArrivedAfterCommit)
                savedTrackReceipt = outcome.track
                savedReceipt = Self.receipt(for: outcome)
                receiptCancellationArrivedAfterCommit = cancellationRequested || outcome.cancellationArrivedAfterCommit
                artworkWarning = outcome.artworkWarning
                transferProgress = nil
                preparedDownload = nil
                clearingURLAfterSave = true
                urlText = ""
                clearingURLAfterSave = false
            } catch is CancellationError {
                guard activeJobID == jobID else { return }
                state = .cancelled
            } catch let error as URLError where error.code == .cancelled {
                guard activeJobID == jobID else { return }
                state = .cancelled
            } catch {
                guard activeJobID == jobID else { return }
                if cancellationRequested {
                    state = .cancelled
                } else {
                    Self.logSafeDiagnostic(for: error)
                    state = .failed(Self.userMessage(for: error))
                }
            }
        }
    }

    func downloadPreview() {
        guard job == nil, let preparedDownload, let preparedDownloadAction else { return }
        #if DEBUG
        fixtureDriver?.reset()
        #endif
        let jobID = UUID()
        savedTrackReceipt = nil
        savedReceipt = nil
        receiptCancellationArrivedAfterCommit = false
        activeJobID = jobID
        cancellationRequested = false
        transferProgress = nil
        activeTransferAttempt = -1
        state = .working("Preparing the confirmed download…")
        job = Task { [onJobSettled] in
            defer { finish(jobID: jobID); onJobSettled() }
            do {
                let outcome = try await preparedDownloadAction(preparedDownload, { [weak self] stage in
                    guard let self, self.activeJobID == jobID, !self.cancellationRequested else { return }
                    self.state = .working(Self.progressMessage(for: stage))
                }, { [weak self] event in
                    guard let self, self.activeJobID == jobID, !self.cancellationRequested,
                          event.operationID == preparedDownload.operationID else { return }
                    guard event.attempt >= self.activeTransferAttempt else { return }
                    self.activeTransferAttempt = event.attempt
                    self.transferProgress = event
                })
                guard activeJobID == jobID else { return }
                artworkWarning = outcome.artworkWarning
                state = .completed(outcome.track, cancellationArrivedAfterCommit: cancellationRequested || outcome.cancellationArrivedAfterCommit)
                savedTrackReceipt = outcome.track
                savedReceipt = Self.receipt(for: outcome)
                receiptCancellationArrivedAfterCommit = cancellationRequested || outcome.cancellationArrivedAfterCommit
                self.preparedDownload = nil
                transferProgress = nil
                clearingURLAfterSave = true
                urlText = ""
                clearingURLAfterSave = false
            } catch is CancellationError {
                guard activeJobID == jobID else { return }
                state = .cancelled
            } catch let error as URLError where error.code == .cancelled {
                guard activeJobID == jobID else { return }
                state = .cancelled
            } catch {
                guard activeJobID == jobID else { return }
                if cancellationRequested { state = .cancelled }
                else { Self.logSafeDiagnostic(for: error); state = .failed(Self.userMessage(for: error)) }
            }
        }
    }

    private func startAnalysis(
        _ video: YouTubeVideoURL,
        analyze: @escaping @MainActor (YouTubeVideoURL) async throws -> YouTubePreparedDownload,
        onJobSettled: @escaping @MainActor () -> Void
    ) {
        let jobID = UUID()
        activeJobID = jobID
        state = .working("Getting video information…")
        job = Task { [weak self] in
            defer { self?.finish(jobID: jobID); onJobSettled() }
            do {
                let prepared = try await analyze(video)
                guard let self, self.activeJobID == jobID else { return }
                guard YouTubeVideoURL(self.urlText)?.videoID == video.videoID else {
                    self.state = .ready
                    return
                }
                guard !self.cancellationRequested else { return }
                self.preparedDownload = prepared
                self.state = .previewReady(prepared.preview)
            } catch is CancellationError {
                guard let self, self.activeJobID == jobID else { return }
                self.state = .cancelled
            } catch {
                guard let self, self.activeJobID == jobID else { return }
                if self.cancellationRequested { self.state = .cancelled }
                else { Self.logSafeDiagnostic(for: error); self.state = .failed(Self.userMessage(for: error)) }
            }
        }
    }

    func cancel() {
        guard let job, activeJobID != nil, !cancellationRequested else { return }
        cancellationRequested = true
        state = .cancelling
        #if DEBUG
        fixtureDriver?.cancelOperation()
        #endif
        job.cancel()
    }

    func retry() {
        if preparedDownload != nil { downloadPreview() }
        else { submit() }
    }

    func editURL() {
        preparedDownload = nil
        transferProgress = nil
        state = .ready
    }

    func play(_ track: Track) {
        guard let playback else { return }
        playback.replaceQueue(with: [track])
        playback.play(track)
        switch playback.status {
        case .playing:
            playbackMessage = "Playback started."
        case .failed:
            playbackMessage = "The track is saved, but playback could not be started. Try again from your library."
        default:
            playbackMessage = "The track is saved, but playback did not start. Try again from your library."
        }
    }

    static func userMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return "Download cancelled."
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "VIPOD could not reach YouTube or its audio server. Check your connection, then try again."
            case .timedOut:
                return "The YouTube request timed out. Check your connection and try again."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid:
                return "VIPOD could not establish a secure connection to the YouTube audio server. Try again later."
            default:
                return "The YouTube network request failed (error \(urlError.errorCode)). Try again later."
            }
        }
        guard let error = error as? YouTubeImportError else {
            return "VIPOD could not complete the download or save it to your music library. Try again."
        }
        switch error {
        case .invalidURL: return "Enter a valid link to one public YouTube video."
        case .extraction: return "YouTube could not provide audio for this video. Check that it is public and try again later."
        case .downloadFailed: return "YouTube returned an unusable audio response. Try again later or choose another public video."
        case .httpFailure(let statusCode):
            switch statusCode {
            case 401, 403: return "YouTube refused the audio request (HTTP \(statusCode)). Try again later or choose another public video."
            case 429: return "YouTube is rate-limiting audio requests (HTTP 429). Wait before trying again."
            case 500...599: return "YouTube's audio server is temporarily unavailable (HTTP \(statusCode)). Try again later."
            default: return "YouTube's audio server returned HTTP \(statusCode). Try again later or choose another public video."
            }
        case .noCompatibleAudio: return "This video has no compatible audio. Try another video."
        case .insecureFormat, .invalidAudioContainer: return "The downloaded audio could not be validated. Try another video."
        case .artworkUnavailable: return "The downloaded audio could not be validated. Try another video."
        case .taggingFailed: return "VIPOD could not embed the requested metadata in this audio file."
        case .metadataVerificationFailed: return "VIPOD could not verify embedded metadata, so the audio was not saved."
        case .duplicateImport: return "This audio is already in your music library."
        case .libraryImportFailed: return "The audio could not be validated or added to your library."
        case .runtimeBusy: return "YouTube extraction is still finishing. Wait a moment before trying again."
        case .runtimeUnavailable, .runtimeTimedOut: return "YouTube extraction needs a restart. Close and reopen VIPOD before trying again."
        }
    }

    private func finish(jobID: UUID) {
        guard activeJobID == jobID else { return }
        activeJobID = nil
        cancellationRequested = false
        job = nil
    }

    private static func receipt(for outcome: YouTubeAudioImportOutcome) -> SavedReceipt {
        let format = outcome.extraction.format
        return SavedReceipt(
            track: outcome.track,
            format: "\(format.extensionName.uppercased()) / \(format.audioCodec)",
            bitrate: format.bitrate,
            exactBytes: format.filesize,
            approximateBytes: format.filesizeApprox
        )
    }

    private static func progressMessage(for stage: YouTubeAudioImportService.Stage) -> String {
        switch stage {
        case .extracting: "Extracting video information…"
        case .downloading: "Downloading AAC/M4A audio…"
        case .refreshing: "Refreshing the expired download link…"
        case .importing: "Validating and adding audio to your library…"
        case .preparingArtwork: "Preparing thumbnail artwork…"
        case .tagging: "Embedding music metadata…"
        case .validating: "Verifying embedded metadata and audio…"
        }
    }

    private static func logSafeDiagnostic(for error: Error) {
        if let error = error as? YouTubeImportError {
            switch error {
            case .runtimeBusy: VIPODPythonLog("YouTube production import blocked because the embedded extractor is busy.")
            case .runtimeUnavailable, .runtimeTimedOut: VIPODPythonLog("YouTube production import needs runtime recovery; native details suppressed.")
            case .extraction(let detail): VIPODPythonLog("YouTube production extraction failed: \(safeDiagnosticText(detail))")
            case .downloadFailed: VIPODPythonLog("YouTube production media download failed; response details suppressed.")
            case .httpFailure(let statusCode): VIPODPythonLog("YouTube production media server returned HTTP status \(statusCode); signed URL suppressed.")
            default: VIPODPythonLog("YouTube production import failed validation or library handling.")
            }
        } else if let error = error as? URLError {
            VIPODPythonLog("YouTube production network request failed (URL error code \(error.errorCode)); request details suppressed.")
        } else {
            let error = error as NSError
            VIPODPythonLog("YouTube production import failed (NSError domain \(safeDiagnosticText(error.domain)), code \(error.code)); native details suppressed.")
        }
    }

    private static func safeDiagnosticText(_ text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let urlPattern = #"(?i)https?://[^\s\"'<>]+"#
        let urlSafe = (try? NSRegularExpression(pattern: urlPattern))?.stringByReplacingMatches(
            in: singleLine,
            range: NSRange(singleLine.startIndex..., in: singleLine),
            withTemplate: "<URL redacted>"
        ) ?? "Extraction failed."
        let pathPattern = #"(?:/Users/|/private/|/var/|/tmp/)[^\s\"'<>:,;)]*"#
        let pathSafe = (try? NSRegularExpression(pattern: pathPattern))?.stringByReplacingMatches(
            in: urlSafe,
            range: NSRange(urlSafe.startIndex..., in: urlSafe),
            withTemplate: "<path redacted>"
        ) ?? urlSafe
        return String(pathSafe.prefix(240))
    }
}
#endif
