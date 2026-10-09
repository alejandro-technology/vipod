import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

#if os(iOS)
struct YouTubeAudioImportOutcome: Sendable {
    let track: Track
    let extraction: YouTubeExtractionResult
    let cancellationArrivedAfterCommit: Bool
    var artworkWarning: String? = nil
}

@MainActor
struct YouTubeAudioImportService {
    enum Stage: Equatable {
        case extracting
        case downloading
        case refreshing
        case preparingArtwork
        case tagging
        case validating
        case importing
    }

    struct DownloadProgress: Equatable, Sendable {
        let operationID: UUID
        let attempt: Int
        let completedBytes: Int64
        let expectedBytes: Int64?

        var fractionCompleted: Double? {
            guard let expectedBytes, expectedBytes > 0 else { return nil }
            return min(max(Double(completedBytes) / Double(expectedBytes), 0), 1)
        }
    }

    typealias Extract = @MainActor (YouTubeVideoURL) async throws -> YouTubeExtractionResult
    typealias Download = @MainActor (URLRequest) async throws -> (URL, URLResponse)
    typealias Transfer = @MainActor (URLRequest, UUID, Int, @escaping @MainActor (DownloadProgress) -> Void) async throws -> (URL, URLResponse)
    typealias Import = @MainActor (URL) async -> TrackImportReport?
    typealias Tag = @MainActor (URL, YouTubeEffectiveMetadata, Data?) async throws -> URL
    typealias Artwork = @MainActor (URL) async throws -> Data
    typealias PassthroughAAC = @MainActor (URL) async throws -> Bool

    private let extract: Extract
    private let downloadRequest: Transfer
    private let importFile: Import
    private let tagFile: Tag
    private let fetchArtwork: Artwork
    private let isPassthroughAAC: PassthroughAAC

    init(library: LibraryController, extractor: EmbeddedYouTubeExtractor = .shared) {
        self.extract = { try await extractor.extract($0) }
        self.downloadRequest = { request, operationID, attempt, progress in
            let delegate = YouTubeTransferDelegate(operationID: operationID, attempt: attempt, progress: progress)
            return try await URLSession.shared.download(for: request, delegate: delegate)
        }
        self.importFile = { await library.importTracks(from: [$0]) }
        self.tagFile = { source, metadata, artwork in
            try await YouTubeM4AMetadataWriter().write(sourceURL: source, metadata: metadata, artwork: artwork)
        }
        self.fetchArtwork = Self.downloadArtwork
        self.isPassthroughAAC = YouTubeM4AMetadataWriter.isPassthroughCompatibleAAC
    }

    /// Dependency-injected compatibility initializer for deterministic service tests.
    /// Tests must provide a tag closure when exercising tagged-media behavior.
    init(
        extract: @escaping Extract,
        download: @escaping Download,
        importFile: @escaping Import,
        tag: @escaping Tag = { source, _, _ in source },
        artwork: @escaping Artwork = { _ in throw YouTubeImportError.artworkUnavailable },
        passthroughAAC: @escaping PassthroughAAC = { _ in true }
    ) {
        self.extract = extract
        self.downloadRequest = { request, operationID, attempt, progress in
            let (url, response) = try await download(request)
            let expected = response.expectedContentLength > 0 ? response.expectedContentLength : nil
            progress(DownloadProgress(operationID: operationID, attempt: attempt, completedBytes: expected ?? 0, expectedBytes: expected))
            return (url, response)
        }
        self.importFile = importFile
        self.tagFile = tag
        self.fetchArtwork = artwork
        self.isPassthroughAAC = passthroughAAC
    }

    func analyze(_ video: YouTubeVideoURL) async throws -> YouTubePreparedDownload {
        try Task.checkCancellation()
        let extraction = try await extract(video)
        try Task.checkCancellation()
        guard extraction.id == video.videoID else { throw YouTubeImportError.extraction("The extracted video did not match the requested video.") }
        let music = extraction.music
        let track = Self.parseOrdinal(music?.trackNumber, maximum: 9999)
        let disc = Self.parseOrdinal(music?.discNumber, maximum: 999)
        let effective = YouTubeEffectiveMetadata(
            title: music?.title, videoTitle: extraction.title,
            artist: music?.artist, album: music?.album, albumArtist: music?.albumArtist,
            releaseDate: music?.date, genre: music?.genre,
            trackNumber: track?.value, discNumber: disc?.value,
            trackNumberTotal: track?.total, discNumberTotal: disc?.total
        )
        let preview = YouTubeVideoPreview(
            videoID: extraction.id,
            videoTitle: extraction.title,
            duration: extraction.duration,
            thumbnailURL: Self.safeThumbnailURL(extraction.thumbnail),
            channel: extraction.channel,
            uploadDate: extraction.uploadDate,
            effectiveMetadata: effective,
            formats: extraction.formats.map {
                YouTubePreviewFormat(formatID: $0.formatID, bitrate: $0.bitrate, filesize: $0.filesize, filesizeApprox: $0.filesizeApprox)
            }
        )
        return YouTubePreparedDownload(preview: preview, operationID: UUID(), extractedAt: Date(), extraction: extraction)
    }

    func download(
        _ prepared: YouTubePreparedDownload,
        update: @MainActor (Stage) -> Void,
        progress: @escaping @MainActor (DownloadProgress) -> Void = { _ in }
    ) async throws -> YouTubeAudioImportOutcome {
        var temporaryFiles = YouTubeTemporaryFileScope()
        defer { temporaryFiles.cleanup() }

        var extraction = prepared.extraction
        var attemptedURLs = Set<URL>()
        var triedCandidates = 0
        var didRefreshExtraction = false
        var finalHTTPStatus: Int?
        var selectedURL: URL?
        var rejectedNonPassthroughCodec = false
        var warning: String?
        let maximumMediaRequests = 4
        let maximumRankedCandidatesPerExtraction = 3

        for attempt in 0..<maximumMediaRequests {
            var format = extraction.formats.first(where: { !attemptedURLs.contains($0.url) })
            if format == nil || triedCandidates >= maximumRankedCandidatesPerExtraction {
                guard !didRefreshExtraction else {
                    if let finalHTTPStatus { throw YouTubeImportError.httpFailure(finalHTTPStatus) }
                    if rejectedNonPassthroughCodec { throw YouTubeImportError.noCompatibleAudio }
                    throw YouTubeImportError.downloadFailed
                }
                update(.refreshing)
                let refreshed = try await extract(YouTubeVideoURL("https://youtu.be/\(prepared.preview.videoID)")!)
                try Task.checkCancellation()
                extraction = refreshed.selecting(refreshed.formats.first ?? refreshed.format)
                    .preserving(prepared.extraction, identity: prepared.preview.videoID)
                didRefreshExtraction = true
                triedCandidates = 0
                format = extraction.formats.first(where: { !attemptedURLs.contains($0.url) })
            }
            guard let format else {
                if let finalHTTPStatus { throw YouTubeImportError.httpFailure(finalHTTPStatus) }
                throw YouTubeImportError.downloadFailed
            }
            attemptedURLs.insert(format.url)
            triedCandidates += 1
            update(.downloading)
            var request = URLRequest(url: format.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
            format.httpHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            progress(DownloadProgress(operationID: prepared.operationID, attempt: attempt, completedBytes: 0, expectedBytes: format.filesize))
            let (candidateURL, response) = try await downloadRequest(request, prepared.operationID, attempt, progress)
            temporaryFiles.track(candidateURL)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw YouTubeImportError.downloadFailed }
            guard http.url?.scheme?.lowercased() == "https" else { throw YouTubeImportError.insecureFormat }
            if (http.statusCode == 401 || http.statusCode == 403), attempt < maximumMediaRequests - 1 {
                try temporaryFiles.remove(candidateURL)
                finalHTTPStatus = http.statusCode
                continue
            }
            guard (200..<300).contains(http.statusCode) else { throw YouTubeImportError.httpFailure(http.statusCode) }
            finalHTTPStatus = nil
            let signature: Data
            do {
                let handle = try FileHandle(forReadingFrom: candidateURL)
                defer { try? handle.close() }
                signature = try handle.read(upToCount: 12) ?? Data()
            }
            guard YouTubeAudioContainer.hasM4AFileType(signature) else { throw YouTubeImportError.invalidAudioContainer }
            let sourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("vipod-source-\(UUID().uuidString).m4a")
            do { try temporaryFiles.move(candidateURL, to: sourceURL) }
            catch { throw YouTubeImportError.downloadFailed }
            try Task.checkCancellation()
            guard (try? await isPassthroughAAC(sourceURL)) == true else {
                try temporaryFiles.remove(sourceURL)
                rejectedNonPassthroughCodec = true
                VIPODPythonLog("Rejected yt-dlp-ranked M4A format \(format.formatID) because the downloaded audio subtype cannot be passed through as AAC-LC; signed URL and headers suppressed.")
                continue
            }
            selectedURL = sourceURL
            extraction = extraction.selecting(format)
            break
        }

        guard let sourceURL = selectedURL else {
            if rejectedNonPassthroughCodec { throw YouTubeImportError.noCompatibleAudio }
            throw YouTubeImportError.downloadFailed
        }

        var artwork: Data?
        if let thumbnailURL = prepared.preview.thumbnailURL {
            update(.preparingArtwork)
            do { artwork = try await fetchArtwork(thumbnailURL) }
            catch is CancellationError { throw CancellationError() }
            catch {
                warning = "Artwork could not be downloaded; the audio will be saved without artwork."
            }
        } else {
            warning = "No video thumbnail was available; the audio will be saved without artwork."
        }

        update(.tagging)
        let taggedURL: URL
        do {
            taggedURL = try await tagFile(sourceURL, prepared.preview.effectiveMetadata, artwork)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as YouTubeM4AMetadataWriter.WriterError {
            switch error {
            case .verificationFailed(let detail):
                VIPODPythonLog("YouTube M4A metadata readback failed: \(detail)")
                Self.captureReadbackDiagnosticIfRequested(source: sourceURL, metadata: prepared.preview.effectiveMetadata, artwork: artwork)
                throw YouTubeImportError.metadataVerificationFailed
            case .invalidArtwork, .invalidSource, .exportUnavailable, .exportFailed: throw YouTubeImportError.taggingFailed
            }
        } catch let error as YouTubeImportError {
            throw error
        } catch {
            throw YouTubeImportError.taggingFailed
        }
        Self.captureReadbackDiagnosticIfRequested(source: sourceURL, metadata: prepared.preview.effectiveMetadata, artwork: artwork)
        temporaryFiles.track(taggedURL)
        try Task.checkCancellation()

        update(.validating)
        let taggedSignature = Data(try Data(contentsOf: taggedURL, options: .mappedIfSafe).prefix(12))
        guard YouTubeAudioContainer.hasM4AFileType(taggedSignature) else {
            throw YouTubeImportError.invalidAudioContainer
        }
        update(.importing)
        guard let report = await importFile(taggedURL) else {
            throw YouTubeImportError.libraryImportFailed("The library rejected this import job.")
        }
        if let track = report.imported.first {
            return YouTubeAudioImportOutcome(track: track, extraction: extraction, cancellationArrivedAfterCommit: report.wasCancelled || Task.isCancelled, artworkWarning: warning)
        }
        if report.wasCancelled || Task.isCancelled { throw CancellationError() }
        if report.failures.contains(where: { $0.reason == .duplicate }) { throw YouTubeImportError.duplicateImport }
        throw YouTubeImportError.libraryImportFailed(report.failures.first?.message ?? "The downloaded audio was not imported.")
    }

    /// Preserves the diagnostic/test entry point but routes through prepared extraction reuse.
    func run(_ video: YouTubeVideoURL, update: @MainActor (Stage) -> Void) async throws -> YouTubeAudioImportOutcome {
        update(.extracting)
        return try await download(analyze(video), update: update)
    }

    private static func parseOrdinal(_ value: String?, maximum: Int) -> (value: Int, total: Int?)? {
        guard let value else { return nil }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count <= 2,
              let number = Int(components[0]), number > 0,
              String(number) == components[0] else { return nil }
        var total: Int?
        if components.count == 2 {
            guard let parsedTotal = Int(components[1]), parsedTotal >= number,
                  String(parsedTotal) == components[1] else { return nil }
            total = parsedTotal
        }
        guard number <= maximum, total.map({ $0 <= maximum }) ?? true else { return nil }
        return (number, total)
    }

    private static func safeThumbnailURL(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https",
              ["i.ytimg.com", "img.youtube.com"].contains(url.host?.lowercased() ?? "") else { return nil }
        return url
    }

    private static func downloadArtwork(_ url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https",
              ["i.ytimg.com", "img.youtube.com"].contains(url.host?.lowercased() ?? "") else { throw YouTubeImportError.artworkUnavailable }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("image/avif,image/webp,image/*", forHTTPHeaderField: "Accept")
        let delegate = BoundedArtworkDelegate()
        let boundedSession = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { boundedSession.invalidateAndCancel() }
        let data = try await delegate.load(from: boundedSession, request: request)
        try Task.checkCancellation()
        guard data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw YouTubeImportError.artworkUnavailable }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0, width <= 20_000, height <= 20_000,
              width.multipliedReportingOverflow(by: height).overflow == false,
              width * height <= 100_000_000 else { throw YouTubeImportError.artworkUnavailable }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { throw YouTubeImportError.artworkUnavailable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw YouTubeImportError.artworkUnavailable }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw YouTubeImportError.artworkUnavailable }
        return output as Data
    }

    static func safeFilename(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_()"))
        let cleaned = String(title.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return String((cleaned.isEmpty ? "YouTube Audio" : cleaned).prefix(100))
    }

    static func challengeSummary(_ result: YouTubeExtractionResult) -> String {
        result.webkitJSCChallengeCalls > 0
            ? "Apple WebKit solved \(result.webkitJSCChallengeSuccesses)/\(result.webkitJSCChallengeCalls) N/Sig challenges"
            : "Apple WebKit N/Sig challenge not exercised by this video"
    }

    private static func captureReadbackDiagnosticIfRequested(
        source: URL,
        metadata: YouTubeEffectiveMetadata,
        artwork: Data?
    ) {
        #if DEBUG
        let isExplicitUITest = ProcessInfo.processInfo.arguments.contains("--uitesting-library-fixture")
        guard ProcessInfo.processInfo.environment["VIPOD_CAPTURE_YOUTUBE_M4A_READBACK"] == "1" || isExplicitUITest,
              let attributes = try? FileManager.default.attributesOfItem(atPath: source.path),
              ((attributes[.size] as? NSNumber)?.int64Value ?? Int64.max) <= 32 * 1024 * 1024 else { return }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VIPOD-YouTube-Readback-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            try FileManager.default.copyItem(at: source, to: root.appendingPathComponent("source.m4a"))
            if let artwork { try artwork.write(to: root.appendingPathComponent("artwork.jpg"), options: .atomic) }
            var snapshot: [String: String] = ["title": metadata.title]
            if let artist = metadata.artist { snapshot["artist"] = artist }
            if let album = metadata.album { snapshot["album"] = album }
            if let albumArtist = metadata.albumArtist { snapshot["albumArtist"] = albumArtist }
            if let releaseDate = metadata.releaseDate { snapshot["releaseDate"] = releaseDate }
            if let genre = metadata.genre { snapshot["genre"] = genre }
            if let number = metadata.trackNumber {
                snapshot["trackNumber"] = metadata.trackNumberTotal.map { "\(number)/\($0)" } ?? "\(number)"
            }
            if let number = metadata.discNumber {
                snapshot["discNumber"] = metadata.discNumberTotal.map { "\(number)/\($0)" } ?? "\(number)"
            }
            let snapshotData = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
            try snapshotData.write(to: root.appendingPathComponent("effective-tags.json"), options: .atomic)
            VIPODPythonLog("Bounded M4A readback diagnostic capture stored at \(root.path); request URL and headers were not captured.")
        } catch {
            try? FileManager.default.removeItem(at: root)
            VIPODPythonLog("M4A readback diagnostic capture failed; signed request data was not captured.")
        }
        #endif
    }
}

private final class YouTubeTransferDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let operationID: UUID
    private let attempt: Int
    private let progress: @MainActor (YouTubeAudioImportService.DownloadProgress) -> Void

    init(operationID: UUID, attempt: Int, progress: @escaping @MainActor (YouTubeAudioImportService.DownloadProgress) -> Void) {
        self.operationID = operationID
        self.attempt = attempt
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        let event = YouTubeAudioImportService.DownloadProgress(operationID: operationID, attempt: attempt, completedBytes: max(0, totalBytesWritten), expectedBytes: expected)
        Task { @MainActor [progress] in progress(event) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

private final class BoundedArtworkDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var rejected = false

    func load(from session: URLSession, request: URLRequest) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                let task = session.dataTask(with: request)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.lock.lock(); let task = self.task; self.lock.unlock()
            task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              (response.expectedContentLength <= 8 * 1024 * 1024 || response.expectedContentLength < 0),
              let mime = response.mimeType?.lowercased(), mime.hasPrefix("image/") else {
            lock.lock(); rejected = true; lock.unlock()
            completionHandler(.cancel)
            return
        }
        lock.lock(); self.response = http; lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        if self.data.count + data.count > 8 * 1024 * 1024 {
            rejected = true
            lock.unlock()
            dataTask.cancel()
            return
        }
        self.data.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              ["i.ytimg.com", "img.youtube.com"].contains(url.host?.lowercased() ?? "") else {
            lock.lock(); rejected = true; lock.unlock()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let result: Result<Data, Error>
        if rejected { result = .failure(YouTubeImportError.artworkUnavailable) }
        else if let error { result = .failure(error) }
        else if response != nil, !data.isEmpty { result = .success(data) }
        else { result = .failure(YouTubeImportError.artworkUnavailable) }
        lock.unlock()
        continuation?.resume(with: result)
    }
}

private extension YouTubeExtractionResult {
    func preserving(_ original: YouTubeExtractionResult, identity: String) -> YouTubeExtractionResult {
        YouTubeExtractionResult(
            id: identity, title: original.title, format: format, formats: formats,
            webkitJSCChallengeCalls: webkitJSCChallengeCalls,
            webkitJSCChallengeSuccesses: webkitJSCChallengeSuccesses,
            duration: original.duration, thumbnail: original.thumbnail, channel: original.channel,
            uploadDate: original.uploadDate, music: original.music
        )
    }
}
#endif
