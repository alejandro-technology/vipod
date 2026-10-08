import Foundation
import Observation

#if os(iOS)
@MainActor @Observable
final class YouTubeDownloadController {
    enum State: Equatable {
        case ready
        case working(String)
        case cancelling
        case cancelled
        case failed(String)
        case completed(Track, cancellationArrivedAfterCommit: Bool)
    }

    private(set) var state: State = .ready
    private(set) var playbackMessage: String?
    var urlText = ""

    private let download: @MainActor (YouTubeVideoURL, @escaping @MainActor (YouTubeAudioImportService.Stage) -> Void) async throws -> YouTubeAudioImportOutcome
    private let playback: PlaybackController?
    private let onJobSettled: @MainActor () -> Void
    private var job: Task<Void, Never>?
    private var activeJobID: UUID?
    private var cancellationRequested = false

    init(
        playback: PlaybackController? = nil,
        onJobSettled: @escaping @MainActor () -> Void = {},
        download: @escaping @MainActor (YouTubeVideoURL, @escaping @MainActor (YouTubeAudioImportService.Stage) -> Void) async throws -> YouTubeAudioImportOutcome
    ) {
        self.playback = playback
        self.onJobSettled = onJobSettled
        self.download = download
    }

    nonisolated deinit {}

    var isBusy: Bool { job != nil }

    func submit() {
        guard job == nil else { return }
        guard let video = YouTubeVideoURL(urlText) else {
            state = .failed("Enter a valid link to one public YouTube video.")
            return
        }

        let jobID = UUID()
        activeJobID = jobID
        cancellationRequested = false
        playbackMessage = nil
        state = .working("Extracting video information…")
        job = Task { [download, onJobSettled] in
            defer {
                finish(jobID: jobID)
                onJobSettled()
            }
            do {
                let outcome = try await download(video) { [weak self] stage in
                    guard let self, self.activeJobID == jobID, !self.cancellationRequested else { return }
                    self.state = .working(Self.progressMessage(for: stage))
                }
                // A durable repository result wins over a cancellation request that arrived
                // while the library was committing its catalog transaction.
                guard activeJobID == jobID else { return }
                state = .completed(outcome.track, cancellationArrivedAfterCommit: cancellationRequested || outcome.cancellationArrivedAfterCommit)
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

    func cancel() {
        guard let job, activeJobID != nil, !cancellationRequested else { return }
        cancellationRequested = true
        state = .cancelling
        job.cancel()
    }

    func retry() { submit() }
    func editURL() { state = .ready }

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

    private static func progressMessage(for stage: YouTubeAudioImportService.Stage) -> String {
        switch stage {
        case .extracting: "Extracting video information…"
        case .downloading: "Downloading AAC/M4A audio…"
        case .refreshing: "Refreshing the expired download link…"
        case .importing: "Validating and adding audio to your library…"
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
