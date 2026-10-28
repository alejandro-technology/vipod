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

    enum MusicBrainzSearchState: Equatable {
        case idle
        case searching
        case results
        case noResults
        case failed(String)
    }

    enum ArtworkSource: Equatable {
        case youtube
        case musicBrainz
    }

    private(set) var state: State = .ready
    private(set) var playbackMessage: String?
    private(set) var savedTrackReceipt: Track?
    private(set) var savedReceipt: SavedReceipt?
    private(set) var receiptCancellationArrivedAfterCommit = false
    private(set) var metadataDraft: YouTubeMetadataDraft?
    private(set) var musicBrainzSearchState: MusicBrainzSearchState = .idle
    private(set) var musicBrainzRecordings: [YouTubeMusicRecording] = []
    private(set) var selectedMusicBrainzRecordingID: String?
    private(set) var selectedMusicBrainzReleaseID: String?
    private(set) var selectedMusicBrainzTrackID: String?
    private(set) var selectedMusicBrainzRelease: YouTubeMusicReleaseDetails?
    private(set) var isLoadingMusicBrainzRelease = false
    private(set) var isLoadingMusicBrainzArtwork = false
    private(set) var musicBrainzArtworkMessage: String?
    private(set) var musicBrainzErrorMessage: String?
    private(set) var hasMusicBrainzArtwork = false
    private(set) var selectedArtworkSource: ArtworkSource = .youtube
    private(set) var musicBrainzArtwork: Data?
    var musicBrainzQuery = "" {
        didSet {
            guard musicBrainzQuery != oldValue else { return }
            invalidateMusicBrainzResults()
        }
    }
    var urlText = "" {
        didSet {
            guard urlText != oldValue, !clearingURLAfterSave else { return }
            let newVideoID = YouTubeVideoURL(urlText)?.videoID
            if let preparedDownload, preparedDownload.preview.videoID != newVideoID {
                self.preparedDownload = nil
                metadataDraft = nil
                musicBrainzArtwork = nil
                hasMusicBrainzArtwork = false
                selectedArtworkSource = .youtube
                musicBrainzQuery = ""
            }
            if let musicBrainzVideoID, musicBrainzVideoID != newVideoID {
                musicBrainzQuery = ""
                invalidateMusicBrainzResults()
            }
            transferProgress = nil
            if case .working = state { return }
            if case .cancelling = state { return }
            if preparedDownload == nil { state = .ready }
        }
    }

    private let legacyDownload: (@MainActor (YouTubeVideoURL, @escaping @MainActor (YouTubeAudioImportService.Stage) -> Void) async throws -> YouTubeAudioImportOutcome)?
    private let analyze: (@MainActor (YouTubeVideoURL) async throws -> YouTubePreparedDownload)?
    private let preparedDownloadAction: (@MainActor (YouTubePreparedDownload, YouTubeEffectiveMetadata, Data?, @escaping @MainActor (YouTubeAudioImportService.Stage) -> Void, @escaping @MainActor (YouTubeAudioImportService.DownloadProgress) -> Void) async throws -> YouTubeAudioImportOutcome)?
    private let musicMetadataSearch: (any YouTubeMusicMetadataSearching)?
    private let playback: PlaybackController?
    private let onJobSettled: @MainActor () -> Void
    private var job: Task<Void, Never>?
    private var activeJobID: UUID?
    private var cancellationRequested = false
    private var preparedDownload: YouTubePreparedDownload?
    private var musicBrainzVideoID: String?
    private var musicBrainzGeneration = 0
    private var musicBrainzSearchTask: Task<Void, Never>?
    private var musicBrainzReleaseTask: Task<Void, Never>?
    private var musicBrainzArtworkTask: Task<Void, Never>?
    private var artworkSelectionRevision = 0
    private var clearingURLAfterSave = false
    private var activeTransferAttempt = -1
    private(set) var transferProgress: YouTubeAudioImportService.DownloadProgress?
    private(set) var artworkWarning: String?
    #if DEBUG
    private var fixtureDriver: YouTubeDownloadUITestFixture?
    var fixtureStage: String? { fixtureDriver?.stage.rawValue }
    var fixtureCanAdvance: Bool { fixtureDriver?.canAdvance ?? false }

    init(
        playback: PlaybackController?,
        fixtureDriver: YouTubeDownloadUITestFixture,
        musicMetadataSearch: (any YouTubeMusicMetadataSearching)? = nil
    ) {
        self.playback = playback
        self.onJobSettled = {}
        self.legacyDownload = nil
        self.analyze = { video in
            let format = YouTubeAudioFormat(formatID: "fixture", extensionName: "m4a", protocolName: "https", audioCodec: "mp4a.40.2", videoCodec: "none", url: URL(string: "https://fixture.invalid/not-requested")!, httpHeaders: [:], filesize: 4_000, bitrate: 128)
            let extraction = YouTubeExtractionResult(id: video.videoID, title: "Fixture Video", format: format, formats: [format], webkitJSCChallengeCalls: 0, webkitJSCChallengeSuccesses: 0, duration: 93, thumbnail: nil, channel: "Fixture Channel", uploadDate: nil, music: YouTubeMusicMetadata(title: YouTubeDownloadUITestFixture.receiptTrackTitle, artist: "Fixture Artist", album: "Fixture Album", albumArtist: nil, date: nil, genre: nil, trackNumber: nil, discNumber: nil))
            let preview = YouTubeVideoPreview(videoID: video.videoID, videoTitle: extraction.title, duration: extraction.duration, thumbnailURL: nil, channel: extraction.channel, uploadDate: nil, effectiveMetadata: YouTubeEffectiveMetadata(title: YouTubeDownloadUITestFixture.receiptTrackTitle, videoTitle: extraction.title, artist: "Fixture Artist", album: "Fixture Album", albumArtist: nil, releaseDate: nil, genre: nil, trackNumber: nil, discNumber: nil, trackNumberTotal: nil, discNumberTotal: nil), formats: [YouTubePreviewFormat(formatID: "fixture", bitrate: 128, filesize: 4_000, filesizeApprox: nil)])
            return YouTubePreparedDownload(preview: preview, operationID: UUID(), extractedAt: Date(), extraction: extraction)
        }
        self.musicMetadataSearch = musicMetadataSearch
        self.fixtureDriver = fixtureDriver
        self.preparedDownloadAction = { prepared, metadata, artworkOverride, update, progress in
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
            let tagged = try await YouTubeM4AMetadataWriter().write(sourceURL: source, metadata: metadata, artwork: artworkOverride, temporaryDirectory: root)
            let report = await driver.importFile(tagged)
            guard let track = report?.imported.first else { throw YouTubeImportError.libraryImportFailed("The deterministic UI fixture could not be saved.") }
            return YouTubeAudioImportOutcome(track: track, extraction: prepared.extraction, cancellationArrivedAfterCommit: false, artworkWarning: artworkOverride == nil ? "No video thumbnail was available; the audio was saved without artwork." : nil)
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
        self.musicMetadataSearch = nil
    }

    init(
        playback: PlaybackController? = nil,
        onJobSettled: @escaping @MainActor () -> Void = {},
        analyze: @escaping @MainActor (YouTubeVideoURL) async throws -> YouTubePreparedDownload,
        musicMetadataSearch: (any YouTubeMusicMetadataSearching)? = nil,
        downloadPrepared: @escaping @MainActor (
            YouTubePreparedDownload,
            YouTubeEffectiveMetadata,
            Data?,
            @escaping @MainActor (YouTubeAudioImportService.Stage) -> Void,
            @escaping @MainActor (YouTubeAudioImportService.DownloadProgress) -> Void
        ) async throws -> YouTubeAudioImportOutcome
    ) {
        self.playback = playback
        self.onJobSettled = onJobSettled
        self.legacyDownload = nil
        self.analyze = analyze
        self.preparedDownloadAction = downloadPrepared
        self.musicMetadataSearch = musicMetadataSearch
    }

    init(
        playback: PlaybackController? = nil,
        onJobSettled: @escaping @MainActor () -> Void = {},
        service: YouTubeAudioImportService,
        musicMetadataSearch: (any YouTubeMusicMetadataSearching)? = nil
    ) {
        self.playback = playback
        self.onJobSettled = onJobSettled
        self.legacyDownload = nil
        self.analyze = { try await service.analyze($0) }
        self.preparedDownloadAction = { prepared, metadata, artwork, update, progress in
            try await service.download(prepared, metadata: metadata, artworkOverride: artwork, update: update, progress: progress)
        }
        self.musicMetadataSearch = musicMetadataSearch
    }

    #if DEBUG
    init(
        onJobSettled: @escaping @MainActor () -> Void = {},
        analyze: @escaping @MainActor (YouTubeVideoURL) async throws -> YouTubePreparedDownload,
        musicMetadataSearch: (any YouTubeMusicMetadataSearching)? = nil,
        downloadPrepared: @escaping @MainActor (YouTubePreparedDownload, YouTubeEffectiveMetadata, Data?, @escaping @MainActor (YouTubeAudioImportService.Stage) -> Void, @escaping @MainActor (YouTubeAudioImportService.DownloadProgress) -> Void) async throws -> YouTubeAudioImportOutcome
    ) {
        self.playback = nil
        self.onJobSettled = onJobSettled
        self.legacyDownload = nil
        self.analyze = analyze
        self.preparedDownloadAction = downloadPrepared
        self.musicMetadataSearch = musicMetadataSearch
    }
    #endif

    nonisolated deinit {}

    var isBusy: Bool { job != nil }
    var previewExists: Bool { preparedDownload != nil }
    var retainedPreview: YouTubeVideoPreview? { preparedDownload?.preview }
    var isPreviewReady: Bool { if case .previewReady = state { return true }; return false }
    var metadataValidationMessage: String? { metadataDraft?.validationMessage }
    var isMetadataValid: Bool { metadataDraft?.validationMessage == nil && metadataDraft != nil }
    var canApplyMusicBrainzSelection: Bool {
        guard let release = selectedMusicBrainzRelease,
              let trackID = selectedMusicBrainzTrackID else { return false }
        return release.tracks.contains(where: { $0.id == trackID })
    }

    func updateMetadataDraft(_ keyPath: WritableKeyPath<YouTubeMetadataDraft, String>, value: String) {
        guard job == nil, var draft = metadataDraft else { return }
        draft[keyPath: keyPath] = value
        metadataDraft = draft
    }

    func searchMusicBrainz() {
        guard job == nil, let preparedDownload, let musicMetadataSearch else {
            musicBrainzSearchState = .failed("MusicBrainz search is unavailable. You can still edit the metadata manually.")
            return
        }
        let query = musicBrainzQuery
        guard !YouTubeMusicSearchTitle.sanitized(query).isEmpty else {
            musicBrainzSearchState = .failed("Enter a title to search MusicBrainz.")
            return
        }

        invalidateMusicBrainzResults()
        let videoID = preparedDownload.preview.videoID
        musicBrainzVideoID = videoID
        musicBrainzSearchState = .searching
        let generation = musicBrainzGeneration
        musicBrainzSearchTask = Task { [weak self] in
            do {
                let recordings = try await musicMetadataSearch.searchRecordings(query: query)
                guard let self,
                      self.isCurrentMusicBrainzRequest(generation: generation, videoID: videoID, query: query) else { return }
                self.musicBrainzRecordings = recordings
                self.musicBrainzSearchState = recordings.isEmpty ? .noResults : .results
                self.musicBrainzErrorMessage = nil
                self.musicBrainzSearchTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.isCurrentMusicBrainzRequest(generation: generation, videoID: videoID, query: query) else { return }
                self.musicBrainzSearchState = .failed("MusicBrainz could not be reached. Try again or edit the metadata manually.")
                self.musicBrainzSearchTask = nil
            }
        }
    }

    func selectMusicBrainzRecording(_ recordingID: String) {
        guard job == nil,
              let recording = musicBrainzRecordings.first(where: { $0.id == recordingID }) else { return }
        invalidateMusicBrainzRequests()
        selectedMusicBrainzRecordingID = recording.id
        selectedMusicBrainzReleaseID = nil
        selectedMusicBrainzTrackID = nil
        selectedMusicBrainzRelease = nil
        musicBrainzArtwork = nil
        hasMusicBrainzArtwork = false
        selectedArtworkSource = .youtube
        musicBrainzErrorMessage = nil
    }

    func selectMusicBrainzRelease(_ releaseID: String) {
        guard job == nil,
              let recordingID = selectedMusicBrainzRecordingID,
              let recording = musicBrainzRecordings.first(where: { $0.id == recordingID }),
              recording.releases.contains(where: { $0.id == releaseID }),
              let musicMetadataSearch else { return }
        invalidateMusicBrainzRequests()
        selectedMusicBrainzReleaseID = releaseID
        selectedMusicBrainzTrackID = nil
        selectedMusicBrainzRelease = nil
        musicBrainzArtwork = nil
        hasMusicBrainzArtwork = false
        selectedArtworkSource = .youtube
        musicBrainzErrorMessage = nil
        isLoadingMusicBrainzRelease = true
        let generation = musicBrainzGeneration
        let videoID = preparedDownload?.preview.videoID
        musicBrainzReleaseTask = Task { [weak self] in
            do {
                let details = try await musicMetadataSearch.loadRelease(id: releaseID)
                guard let self, self.musicBrainzGeneration == generation,
                      self.preparedDownload?.preview.videoID == videoID,
                      self.selectedMusicBrainzRecordingID == recordingID,
                      self.selectedMusicBrainzReleaseID == releaseID else { return }
                self.selectedMusicBrainzRelease = details
                self.isLoadingMusicBrainzRelease = false
                self.musicBrainzReleaseTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.musicBrainzGeneration == generation,
                      self.preparedDownload?.preview.videoID == videoID,
                      self.selectedMusicBrainzReleaseID == releaseID else { return }
                self.isLoadingMusicBrainzRelease = false
                self.musicBrainzErrorMessage = "MusicBrainz could not load this release. Choose another release or edit metadata manually."
                self.musicBrainzReleaseTask = nil
            }
        }
    }

    func selectMusicBrainzTrack(_ trackID: String) {
        guard job == nil,
              selectedMusicBrainzRelease?.tracks.contains(where: { $0.id == trackID }) == true else { return }
        invalidateMusicBrainzRequests()
        selectedMusicBrainzTrackID = trackID
        applyMusicBrainzSelection()
    }

    private func applyMusicBrainzSelection() {
        guard job == nil,
              let recordingID = selectedMusicBrainzRecordingID,
              let recording = musicBrainzRecordings.first(where: { $0.id == recordingID }),
              let releaseID = selectedMusicBrainzReleaseID,
              let release = selectedMusicBrainzRelease,
              let trackID = selectedMusicBrainzTrackID,
              let track = release.tracks.first(where: { $0.id == trackID }),
              var draft = metadataDraft else { return }

        Self.applyIfAvailable(track.title, to: \.title, in: &draft)
        Self.applyIfAvailable(track.artist ?? recording.artist, to: \.artist, in: &draft)
        Self.applyIfAvailable(release.title, to: \.album, in: &draft)
        Self.applyIfAvailable(release.artist, to: \.albumArtist, in: &draft)
        Self.applyIfAvailable(release.date ?? recording.firstReleaseDate, to: \.releaseDate, in: &draft)
        Self.applyIfAvailable(recording.genre ?? release.genre, to: \.genre, in: &draft)
        if let number = track.number { draft.trackNumber = String(number) }
        if let total = track.numberTotal { draft.trackNumberTotal = String(total) }
        if let number = track.discNumber { draft.discNumber = String(number) }
        if let total = release.discTotal { draft.discNumberTotal = String(total) }
        metadataDraft = draft
        musicBrainzArtworkMessage = nil
        // A newly applied selection must never inherit another release's cover.
        musicBrainzArtwork = nil
        hasMusicBrainzArtwork = false
        selectedArtworkSource = .youtube

        guard let musicMetadataSearch else { return }
        invalidateMusicBrainzRequests()
        let generation = musicBrainzGeneration
        let videoID = preparedDownload?.preview.videoID
        let artworkRevision = artworkSelectionRevision
        isLoadingMusicBrainzArtwork = true
        musicBrainzArtworkTask = Task { [weak self] in
            do {
                let artwork = try await musicMetadataSearch.artwork(releaseID: releaseID)
                guard let self, self.musicBrainzGeneration == generation,
                      self.preparedDownload?.preview.videoID == videoID,
                      self.selectedMusicBrainzReleaseID == releaseID else { return }
                if let artwork {
                    self.musicBrainzArtwork = artwork
                    self.hasMusicBrainzArtwork = true
                    if self.artworkSelectionRevision == artworkRevision {
                        self.selectedArtworkSource = .musicBrainz
                    }
                    self.musicBrainzArtworkMessage = "MusicBrainz cover art selected."
                } else {
                    self.musicBrainzArtworkMessage = "No MusicBrainz cover art is available; the YouTube thumbnail will be used if available."
                }
                self.isLoadingMusicBrainzArtwork = false
                self.musicBrainzArtworkTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.musicBrainzGeneration == generation,
                      self.preparedDownload?.preview.videoID == videoID,
                      self.selectedMusicBrainzReleaseID == releaseID else { return }
                self.isLoadingMusicBrainzArtwork = false
                self.musicBrainzArtworkMessage = "Cover art could not be loaded; the YouTube thumbnail will be used if available."
                self.musicBrainzArtworkTask = nil
            }
        }
    }

    func selectArtworkSource(_ source: ArtworkSource) {
        guard source == .youtube || hasMusicBrainzArtwork else { return }
        artworkSelectionRevision += 1
        selectedArtworkSource = source
    }

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
            preparedDownload = nil
            metadataDraft = nil
            musicBrainzArtwork = nil
            hasMusicBrainzArtwork = false
            selectedArtworkSource = .youtube
            musicBrainzQuery = ""
            invalidateMusicBrainzResults()
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
        guard job == nil, let preparedDownload, let preparedDownloadAction,
              let metadataDraft,
              let effectiveMetadata = metadataDraft.effectiveMetadata(videoTitle: preparedDownload.preview.videoTitle) else {
            if let message = metadataDraft?.validationMessage { state = .failed(message) }
            return
        }
        #if DEBUG
        fixtureDriver?.reset()
        #endif
        let confirmedArtwork = selectedArtworkSource == .musicBrainz ? musicBrainzArtwork : nil
        if musicBrainzSearchState == .searching { musicBrainzSearchState = .idle }
        invalidateMusicBrainzRequests()
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
                let outcome = try await preparedDownloadAction(preparedDownload, effectiveMetadata, confirmedArtwork, { [weak self] stage in
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
                self.metadataDraft = nil
                self.musicBrainzArtwork = nil
                self.hasMusicBrainzArtwork = false
                self.selectedArtworkSource = .youtube
                self.musicBrainzQuery = ""
                self.invalidateMusicBrainzResults()
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
                self.metadataDraft = YouTubeMetadataDraft(metadata: prepared.preview.effectiveMetadata)
                self.musicBrainzArtwork = nil
                self.hasMusicBrainzArtwork = false
                self.selectedArtworkSource = .youtube
                self.musicBrainzQuery = YouTubeMusicSearchTitle.sanitized(prepared.preview.videoTitle)
                self.musicBrainzVideoID = prepared.preview.videoID
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
        metadataDraft = nil
        musicBrainzArtwork = nil
        hasMusicBrainzArtwork = false
        selectedArtworkSource = .youtube
        musicBrainzQuery = ""
        invalidateMusicBrainzResults()
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

    private func invalidateMusicBrainzRequests() {
        musicBrainzGeneration += 1
        musicBrainzSearchTask?.cancel()
        musicBrainzSearchTask = nil
        musicBrainzReleaseTask?.cancel()
        musicBrainzReleaseTask = nil
        musicBrainzArtworkTask?.cancel()
        musicBrainzArtworkTask = nil
        isLoadingMusicBrainzRelease = false
        isLoadingMusicBrainzArtwork = false
    }

    private func invalidateMusicBrainzResults() {
        invalidateMusicBrainzRequests()
        musicBrainzVideoID = nil
        musicBrainzRecordings = []
        selectedMusicBrainzRecordingID = nil
        selectedMusicBrainzReleaseID = nil
        selectedMusicBrainzTrackID = nil
        selectedMusicBrainzRelease = nil
        musicBrainzSearchState = .idle
        musicBrainzErrorMessage = nil
        musicBrainzArtworkMessage = nil
    }

    private func isCurrentMusicBrainzRequest(generation: Int, videoID: String, query: String) -> Bool {
        job == nil
            && musicBrainzGeneration == generation
            && musicBrainzVideoID == videoID
            && preparedDownload?.preview.videoID == videoID
            && musicBrainzQuery == query
    }

    private static func applyIfAvailable(
        _ value: String?,
        to keyPath: WritableKeyPath<YouTubeMetadataDraft, String>,
        in draft: inout YouTubeMetadataDraft
    ) {
        guard let value else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft[keyPath: keyPath] = trimmed
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
