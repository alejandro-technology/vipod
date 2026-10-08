import AVFoundation
import Foundation
import Observation

nonisolated struct YouTubeVideoURL: Equatable, Sendable {
    let videoID: String

    init?(_ rawValue: String) {
        guard let components = URLComponents(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              components.user == nil, components.password == nil, components.port == nil else { return nil }

        guard components.queryItems?.contains(where: { $0.name == "list" }) != true else { return nil }
        let path = components.path.split(separator: "/")
        let id: String?
        if ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(host),
           path.count == 1, path[0] == "watch" {
            id = components.queryItems?.first(where: { $0.name == "v" })?.value
        } else if host == "youtu.be", path.count == 1 {
            id = String(path[0])
        } else {
            return nil
        }
        guard let id, id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
        videoID = id
    }
}

nonisolated struct YouTubeAudioFormat: Decodable, Sendable {
    let formatID: String
    let extensionName: String
    let protocolName: String
    let audioCodec: String
    let videoCodec: String
    let url: URL
    let httpHeaders: [String: String]
    let filesize: Int64?
    let bitrate: Double?
    var sourcePreference: Double? = nil
    var preference: Double? = nil

    enum CodingKeys: String, CodingKey {
        case formatID, protocolName = "protocol", extensionName = "extension", audioCodec, videoCodec, url, httpHeaders, filesize, bitrate, sourcePreference = "source_preference", preference
    }

    var isCompatibleAAC: Bool {
        extensionName == "m4a"
            && protocolName == "https"
            && url.scheme?.lowercased() == "https"
            && audioCodec.lowercased().hasPrefix("mp4a")
            && videoCodec == "none"
            && url.fragment == nil
    }

    static func best(from formats: [YouTubeAudioFormat]) -> YouTubeAudioFormat? {
        // yt-dlp returns formats ordered worst to best using extractor and format
        // preferences as well as bitrate. Preserve that authoritative ranking.
        formats.last(where: \.isCompatibleAAC)
    }
}

nonisolated struct YouTubeFormatCandidate: Decodable, Sendable {
    let formatID: String?
    let extensionName: String?
    let protocolName: String?
    let audioCodec: String?
    let videoCodec: String?
    let url: URL?
    let httpHeaders: [String: String]?
    let filesize: Int64?
    let bitrate: Double?
    var sourcePreference: Double? = nil
    var preference: Double? = nil

    enum CodingKeys: String, CodingKey {
        case formatID, protocolName = "protocol", extensionName = "extension", audioCodec, videoCodec, url, httpHeaders, filesize, bitrate, sourcePreference = "source_preference", preference
    }

    var directAudioFormat: YouTubeAudioFormat? {
        guard let formatID, let extensionName, let protocolName, let audioCodec,
              let videoCodec, let url else { return nil }
        return YouTubeAudioFormat(
            formatID: formatID,
            extensionName: extensionName,
            protocolName: protocolName,
            audioCodec: audioCodec,
            videoCodec: videoCodec,
            url: url,
            httpHeaders: httpHeaders ?? [:],
            filesize: filesize,
            bitrate: bitrate,
            sourcePreference: sourcePreference,
            preference: preference
        )
    }
}

nonisolated struct YouTubeExtractionResult: Sendable {
    let id: String
    let title: String
    let format: YouTubeAudioFormat
    let formats: [YouTubeAudioFormat]
    let webkitJSCChallengeCalls: Int
    let webkitJSCChallengeSuccesses: Int

    func selecting(_ selectedFormat: YouTubeAudioFormat) -> YouTubeExtractionResult {
        YouTubeExtractionResult(
            id: id,
            title: title,
            format: selectedFormat,
            formats: formats,
            webkitJSCChallengeCalls: webkitJSCChallengeCalls,
            webkitJSCChallengeSuccesses: webkitJSCChallengeSuccesses
        )
    }
}

nonisolated struct YouTubeExtraction: Decodable, Sendable {
    let id: String
    let title: String
    let isLive: Bool
    let formats: [YouTubeFormatCandidate]
    let webkitJSCChallengeCalls: Int
    let webkitJSCChallengeSuccesses: Int
}

nonisolated enum YouTubeImportError: LocalizedError {
    case invalidURL
    case extraction(String)
    case noCompatibleAudio
    case insecureFormat
    case invalidAudioContainer
    case downloadFailed
    case httpFailure(Int)
    case duplicateImport
    case libraryImportFailed(String)
    case runtimeBusy
    case runtimeUnavailable
    case runtimeTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a public YouTube single-video URL."
        case .extraction(let message): message
        case .noCompatibleAudio: "No direct HTTPS AAC/M4A audio format is available for this video."
        case .insecureFormat: "The selected audio format did not provide a secure HTTPS URL."
        case .invalidAudioContainer: "The downloaded file is not a valid M4A audio container."
        case .downloadFailed: "The audio download could not be completed."
        case .httpFailure(let statusCode): "The audio server returned HTTP status \(statusCode)."
        case .duplicateImport: "This audio is already in your music library."
        case .libraryImportFailed(let message): message
        case .runtimeBusy: "The previous Python extraction is still running. Wait for it to finish or restart VIPOD."
        case .runtimeUnavailable: "The embedded Python runtime is unavailable after a provider timeout. Restart VIPOD to retry."
        case .runtimeTimedOut: "YouTube extraction exceeded the 120-second diagnostic limit. Check the provider log and restart VIPOD before retrying."
        }
    }
}

nonisolated enum YouTubeSignedURLRetryPolicy {
    static func shouldReextract(statusCode: Int, attempt: Int) -> Bool {
        (statusCode == 401 || statusCode == 403) && attempt == 0
    }
}

nonisolated enum YouTubeAudioContainer {
    static func hasM4AFileType(_ header: Data) -> Bool {
        header.count >= 8 && String(data: header[4..<8], encoding: .ascii) == "ftyp"
    }
}

nonisolated struct YouTubeTemporaryFileScope {
    private(set) var urls: [URL] = []

    mutating func track(_ url: URL) {
        if !urls.contains(url) { urls.append(url) }
    }

    mutating func remove(_ url: URL, fileManager: FileManager = .default) throws {
        try fileManager.removeItem(at: url)
        urls.removeAll { $0 == url }
    }

    mutating func move(_ source: URL, to destination: URL, fileManager: FileManager = .default) throws {
        try fileManager.moveItem(at: source, to: destination)
        urls.removeAll { $0 == source }
        track(destination)
    }

    mutating func cleanup(fileManager: FileManager = .default) {
        for url in urls.reversed() { try? fileManager.removeItem(at: url) }
        urls.removeAll()
    }
}

/// Serializes all CPython access away from the main thread. The WebKit JSC provider
/// uses the main run loop while this worker waits for its callback.
#if os(iOS)
nonisolated private final class ExtractionCompletion<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pendingResult: Result<Value, Error>?

    var isResolved: Bool { lock.withLock { pendingResult != nil } }

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let pending = lock.withLock { () -> Result<Value, Error>? in
            if let pendingResult { return pendingResult }
            self.continuation = continuation
            return nil
        }
        if let pending { continuation.resume(with: pending) }
    }

    @discardableResult
    func resolve(_ result: Result<Value, Error>) -> Bool {
        var accepted = false
        let target = lock.withLock { () -> CheckedContinuation<Value, Error>? in
            guard pendingResult == nil else { return nil }
            accepted = true
            pendingResult = result
            defer { continuation = nil }
            return continuation
        }
        target?.resume(with: result)
        return accepted
    }
}

nonisolated private final class EmbeddedPythonWorkerState: @unchecked Sendable {
    let lock = NSLock()
    var extractionInProgress = false
    var runtimePoisoned = false
}

nonisolated private final class ExtractionTimeout: @unchecked Sendable {
    let workItem: DispatchWorkItem
    init(_ operation: @escaping @Sendable () -> Void) { workItem = DispatchWorkItem(block: operation) }
    func cancel() { workItem.cancel() }
}

nonisolated final class EmbeddedYouTubeExtractor: @unchecked Sendable {
    static let shared = EmbeddedYouTubeExtractor()
    private static let queue = DispatchQueue(label: "vipod.youtube.python", qos: .userInitiated)
    private static let workerState = EmbeddedPythonWorkerState()

    private init() {}

    func extract(_ video: YouTubeVideoURL) async throws -> YouTubeExtractionResult {
        let completion = ExtractionCompletion<YouTubeExtractionResult>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                guard !completion.isResolved else { return }

                let timeout = ExtractionTimeout {
                    Self.workerState.lock.withLock { Self.workerState.runtimePoisoned = true }
                    VIPODPythonLog("Extraction exceeded the 120-second liveness deadline. The interpreter is intentionally marked unavailable instead of starting concurrent calls.")
                    completion.resolve(.failure(YouTubeImportError.runtimeTimedOut))
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(120), execute: timeout.workItem)

                Self.queue.async {
                    guard !completion.isResolved else { timeout.cancel(); return }
                    let canStart = Self.workerState.lock.withLock { () -> Bool in
                        guard !Self.workerState.runtimePoisoned, !Self.workerState.extractionInProgress else { return false }
                        Self.workerState.extractionInProgress = true
                        return true
                    }
                    guard canStart else {
                        timeout.cancel()
                        completion.resolve(.failure(Self.workerState.lock.withLock {
                            Self.workerState.runtimePoisoned ? YouTubeImportError.runtimeUnavailable : YouTubeImportError.runtimeBusy
                        }))
                        return
                    }
                    let result = Result { try Self.extractOnWorker(video) }
                    Self.workerState.lock.withLock { Self.workerState.extractionInProgress = false }
                    timeout.cancel()
                    completion.resolve(result)
                }
            }
        } onCancel: {
            completion.resolve(.failure(CancellationError()))
        }
    }

    private static func extractOnWorker(_ video: YouTubeVideoURL) throws -> YouTubeExtractionResult {
        guard !Thread.isMainThread else { throw YouTubeImportError.extraction("The Python worker unexpectedly ran on the main thread.") }
        var initializationError: NSError?
        guard VIPODPythonInitialize(&initializationError) else {
            throw YouTubeImportError.extraction(initializationError?.localizedDescription ?? "Embedded Python initialization failed.")
        }

        var pythonError: NSError?
        guard let json = VIPODPythonExtract(video.videoID, &pythonError) else {
            throw YouTubeImportError.extraction(pythonError?.localizedDescription ?? "Embedded extraction returned no result.")
        }
        let extraction: YouTubeExtraction
        do { extraction = try JSONDecoder().decode(YouTubeExtraction.self, from: Data(json.utf8)) }
        catch {
            let detail = Self.safeDiagnostic(for: error)
            VIPODPythonLog("Python metadata decoding failed (\(json.utf8.count) UTF-8 bytes): \(detail)")
            throw YouTubeImportError.extraction("Python metadata decoding failed: \(detail)")
        }
        guard !extraction.isLive, extraction.id == video.videoID else {
            throw YouTubeImportError.extraction("Only a single, non-live YouTube video is supported.")
        }
        let usableFormats = extraction.formats.compactMap(\.directAudioFormat)
        guard let format = YouTubeAudioFormat.best(from: usableFormats) else { throw YouTubeImportError.noCompatibleAudio }
        guard format.url.scheme?.lowercased() == "https" else { throw YouTubeImportError.insecureFormat }
        let preference = format.preference.map { String($0) } ?? "unset"
        let sourcePreference = format.sourcePreference.map { String($0) } ?? "unset"
        VIPODPythonLog("Extracted \(extraction.id) (\(extraction.title)); selected yt-dlp-ranked format \(format.formatID) from \(usableFormats.filter(\.isCompatibleAAC).count) compatible HTTPS AAC formats; preference=\(preference), sourcePreference=\(sourcePreference), challenge=\(extraction.webkitJSCChallengeSuccesses)/\(extraction.webkitJSCChallengeCalls). Signed URL suppressed.")
        return YouTubeExtractionResult(
            id: extraction.id,
            title: extraction.title,
            format: format,
            formats: usableFormats.filter(\.isCompatibleAAC).reversed(),
            webkitJSCChallengeCalls: extraction.webkitJSCChallengeCalls,
            webkitJSCChallengeSuccesses: extraction.webkitJSCChallengeSuccesses
        )
    }

    private static func safeDiagnostic(for error: Error) -> String {
        let detail: String
        switch error as? DecodingError {
        case .keyNotFound(let key, _): detail = "Missing metadata field '\(key.stringValue)'."
        case .typeMismatch(let type, let context): detail = "Field type mismatch for \(context.codingPath.map(\.stringValue).joined(separator: ".")) (expected \(type))."
        case .valueNotFound(let type, let context): detail = "Missing value for \(context.codingPath.map(\.stringValue).joined(separator: ".")) (expected \(type))."
        case .dataCorrupted(let context): detail = "Invalid JSON at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
        case .some: detail = error.localizedDescription
        case nil: detail = error.localizedDescription
        }
        let pattern = #"(?i)https?://[^\s\"'<>]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return detail }
        return expression.stringByReplacingMatches(in: detail, range: NSRange(detail.startIndex..., in: detail), withTemplate: "<URL redacted>")
    }
}

@MainActor @Observable
final class YouTubeImportDiagnostic {
    private(set) var status = "Ready. Paste a public YouTube video URL."
    private(set) var importedTrackTitle: String?
    private(set) var latestLocalTrackTitle: String?
    private(set) var isRunning = false
    var urlText = ""

    private let extractor: EmbeddedYouTubeExtractor
    private let library: LibraryController
    private let playback: PlaybackController
    private var job: Task<Void, Never>?

    init(library: LibraryController, playback: PlaybackController, extractor: EmbeddedYouTubeExtractor = .shared) {
        self.library = library
        self.playback = playback
        self.extractor = extractor
    }

    func cancel() {
        job?.cancel()
        status = "Cancelling…"
    }

    func loadSavedLibrary() async {
        await library.load()
        latestLocalTrackTitle = library.tracks.last?.title
        VIPODPythonLog("Diagnostic loaded \(library.tracks.count) saved local library tracks without network access.")
    }

    func playMostRecentLocalTrack() {
        guard let track = library.tracks.last else {
            status = "No saved local track is available to play."
            return
        }
        playback.replaceQueue(with: [track])
        playback.play(track)
        if case .playing = playback.status {
            status = "Saved local audio playback started: \(track.title)."
        } else if case .failed(let message) = playback.status {
            status = "Saved local audio could not be played: \(message)"
        } else {
            status = "Saved local audio did not enter the playing state."
        }
    }

    func run() {
        guard !isRunning else { return }
        guard let video = YouTubeVideoURL(urlText) else {
            status = YouTubeImportError.invalidURL.localizedDescription
            return
        }
        isRunning = true
        importedTrackTitle = nil
        status = "Extracting YouTube metadata in embedded Python…"
        job = Task {
            defer { isRunning = false; job = nil }
            do {
                let service = YouTubeAudioImportService(library: library, extractor: extractor)
                let outcome = try await service.run(video) { [weak self] stage in
                    guard let self else { return }
                    switch stage {
                    case .extracting: break
                    case .downloading: self.status = "Downloading AAC/M4A audio…"
                    case .refreshing: self.status = "Refreshing the expired audio URL…"
                    case .importing: self.status = "Validating and importing into the music library…"
                    }
                }
                let track = outcome.track
                importedTrackTitle = track.title
                latestLocalTrackTitle = library.tracks.last?.title
                if outcome.cancellationArrivedAfterCommit {
                    status = "Import cancellation arrived after “\(track.title)” was saved to the library. The saved track is shown above."
                    VIPODPythonLog("Import cancellation arrived after a track was committed; library report was retained.")
                } else {
                    playback.replaceQueue(with: [track])
                    playback.play(track)
                    switch playback.status {
                    case .playing:
                        VIPODPythonLog("Imported track \(track.id.uuidString); AVFoundation entered playing state. Signed media URL was not persisted or logged.")
                        status = "Imported “\(track.title)” (\(outcome.extraction.id)); playback started; \(YouTubeAudioImportService.challengeSummary(outcome.extraction)). Relaunch in Airplane Mode to verify offline playback."
                    case .failed(let message):
                        status = "Imported “\(track.title)” into the library, but playback failed: \(message)"
                    default:
                        status = "Imported “\(track.title)” into the library, but playback did not enter the playing state."
                    }
                }
            } catch is CancellationError {
                status = "Import cancelled."
            } catch let error as URLError where error.code == .cancelled {
                status = "Import cancelled."
            } catch {
                status = error.localizedDescription
            }
        }
    }

}
#endif
