import Foundation

#if os(iOS)
struct YouTubeAudioImportOutcome: Sendable {
    let track: Track
    let extraction: YouTubeExtractionResult
    let cancellationArrivedAfterCommit: Bool
}

@MainActor
struct YouTubeAudioImportService {
    enum Stage: Equatable {
        case extracting
        case downloading
        case refreshing
        case importing
    }

    typealias Extract = @MainActor (YouTubeVideoURL) async throws -> YouTubeExtractionResult
    typealias Download = @MainActor (URLRequest) async throws -> (URL, URLResponse)
    typealias Import = @MainActor (URL) async -> TrackImportReport?

    private let extract: Extract
    private let download: Download
    private let importFile: Import

    init(library: LibraryController, extractor: EmbeddedYouTubeExtractor = .shared) {
        self.extract = { try await extractor.extract($0) }
        self.download = { try await URLSession.shared.download(for: $0) }
        self.importFile = { await library.importTracks(from: [$0]) }
    }

    init(extract: @escaping Extract, download: @escaping Download, importFile: @escaping Import) {
        self.extract = extract
        self.download = download
        self.importFile = importFile
    }

    func run(
        _ video: YouTubeVideoURL,
        update: @MainActor (Stage) -> Void
    ) async throws -> YouTubeAudioImportOutcome {
        var temporaryFiles = YouTubeTemporaryFileScope()
        defer { temporaryFiles.cleanup() }

        update(.extracting)
        var extraction = try await extract(video)
        try Task.checkCancellation()
        var downloadedURL: URL?

        let maximumMediaRequests = 4
        let maximumRankedCandidatesPerExtraction = 3
        var attemptedURLs = Set<URL>()
        var triedCandidates = 0
        var didRefreshExtraction = false
        var finalHTTPStatus: Int?

        for attempt in 0..<maximumMediaRequests {
            var format = extraction.formats.first(where: { !attemptedURLs.contains($0.url) })
            if format == nil || triedCandidates >= maximumRankedCandidatesPerExtraction {
                guard !didRefreshExtraction else {
                    if let finalHTTPStatus { throw YouTubeImportError.httpFailure(finalHTTPStatus) }
                    throw YouTubeImportError.downloadFailed
                }
                update(.refreshing)
                extraction = try await extract(video)
                try Task.checkCancellation()
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
            update(attempt == 0 ? .downloading : .refreshing)
            var request = URLRequest(url: format.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
            format.httpHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            let (candidateURL, response) = try await download(request)
            temporaryFiles.track(candidateURL)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw YouTubeImportError.downloadFailed }
            let headerCategories = Set(format.httpHeaders.keys.map { headerName -> String in
                switch headerName.lowercased() {
                case "user-agent": "user-agent"
                case "referer": "referer"
                case "origin": "origin"
                case "cookie": "cookie-present"
                default: "other"
                }
            }).sorted().joined(separator: ",")
            VIPODPythonLog("Media HTTP \(http.statusCode) for ranked AAC format \(format.formatID); request header categories=[\(headerCategories)], signed URL and header values suppressed.")
            if (http.statusCode == 401 || http.statusCode == 403), attempt < maximumMediaRequests - 1 {
                try temporaryFiles.remove(candidateURL)
                finalHTTPStatus = http.statusCode
                continue
            }
            guard (200..<300).contains(http.statusCode) else { throw YouTubeImportError.httpFailure(http.statusCode) }
            extraction = extraction.selecting(format)
            downloadedURL = candidateURL
            break
        }

        guard let downloadedURL else { throw YouTubeImportError.downloadFailed }
        let signature: Data
        do {
            let handle = try FileHandle(forReadingFrom: downloadedURL)
            defer { try? handle.close() }
            signature = try handle.read(upToCount: 12) ?? Data()
        }
        guard YouTubeAudioContainer.hasM4AFileType(signature) else { throw YouTubeImportError.invalidAudioContainer }
        VIPODPythonLog("Downloaded and verified an M4A ftyp container.")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vipod-youtube-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        temporaryFiles.track(directory)
        let stagedURL = directory.appendingPathComponent(Self.safeFilename(extraction.title) + ".m4a")
        try temporaryFiles.move(downloadedURL, to: stagedURL)
        try Task.checkCancellation()

        update(.importing)
        guard let report = await importFile(stagedURL) else {
            throw YouTubeImportError.libraryImportFailed("The library rejected this import job.")
        }
        if let track = report.imported.first {
            return YouTubeAudioImportOutcome(
                track: track,
                extraction: extraction,
                cancellationArrivedAfterCommit: report.wasCancelled || Task.isCancelled
            )
        }
        if report.wasCancelled || Task.isCancelled { throw CancellationError() }
        if report.failures.contains(where: { $0.reason == .duplicate }) {
            throw YouTubeImportError.duplicateImport
        }
        let failure = report.failures.first?.message ?? "The downloaded audio was not imported."
        throw YouTubeImportError.libraryImportFailed(
            "Embedded extraction finished (\(Self.challengeSummary(extraction))); library import reported: \(failure)"
        )
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
}
#endif
