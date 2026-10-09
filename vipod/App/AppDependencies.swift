import Foundation
import Observation

#if canImport(MediaPlayer) && os(iOS)
import MediaPlayer
#endif

/// Long-lived production services assembled at the app boundary.
@MainActor
final class AppDependencies {
    let repository: FileTrackRepository
    let engine: AVFoundationAudioPlayback
    let library: LibraryController
    let collections: LibraryCollectionController
    let playback: PlaybackController
    #if os(iOS)
    let youtubeDownloads: YouTubeDownloadController
    #endif
    let audioConnection: AudioConnectionMonitor

    #if canImport(MediaPlayer) && os(iOS)
    private let nowPlayingAdapter: MediaPlayerNowPlayingAdapter
    #endif

    init() throws {
        let repository = try FileTrackRepository(storageURL: try UITestLibraryFixture.storageURLIfRequested())
        let storageURL = repository.storageURL
        let engine = AVFoundationAudioPlayback { track in
            try FileTrackRepository.resolveMediaURL(for: track, in: storageURL)
        }
        let library = LibraryController(repository: repository)
        let collections = LibraryCollectionController(store: FileLibraryCollectionStore(storageURL: storageURL))
        let sessionStore = FilePlaybackSessionStore(url: storageURL.appendingPathComponent("playback-session.json"))
        let playback = PlaybackController(engine: engine, sessionStore: sessionStore)
        let audioConnection = AudioConnectionMonitor()

        self.repository = repository
        self.engine = engine
        self.library = library
        self.collections = collections
        self.playback = playback
        #if os(iOS)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitesting-youtube-download") {
            let driver = YouTubeDownloadUITestFixture(library: library)
            self.youtubeDownloads = YouTubeDownloadController(playback: playback, fixtureDriver: driver)
        } else if arguments.contains("--uitesting-youtube-preview") {
            let previewService = YouTubeAudioImportService(
                extract: { video in
                    let format = YouTubeAudioFormat(
                        formatID: "fixture-aac", extensionName: "m4a", protocolName: "https",
                        audioCodec: "mp4a.40.2", videoCodec: "none",
                        url: URL(string: "https://media.example.test/signed-fixture")!,
                        httpHeaders: [:], filesize: 16_000, bitrate: 128
                    )
                    return YouTubeExtractionResult(
                        id: video.videoID, title: "Fixture Video Title", format: format, formats: [format],
                        webkitJSCChallengeCalls: 0, webkitJSCChallengeSuccesses: 0,
                        duration: 93, thumbnail: nil,
                        channel: "Fixture Source Channel", uploadDate: "20261008",
                        music: YouTubeMusicMetadata(title: "Fixture Track Title", artist: "Fixture Artist", album: "Fixture Album", albumArtist: "Fixture Album Artist", date: "2024-05", genre: "Jazz", trackNumber: "2/10", discNumber: "1/2")
                    )
                },
                download: { _ in throw CancellationError() },
                importFile: { _ in nil }
            )
            self.youtubeDownloads = YouTubeDownloadController(playback: playback, service: previewService)
        } else {
            self.youtubeDownloads = YouTubeDownloadController(playback: playback, service: YouTubeAudioImportService(library: library))
        }
        #else
        self.youtubeDownloads = YouTubeDownloadController(playback: playback, service: YouTubeAudioImportService(library: library))
        #endif
        #endif
        self.audioConnection = audioConnection

        #if canImport(MediaPlayer) && os(iOS)
        let adapter = MediaPlayerNowPlayingAdapter { track in
            try FileTrackRepository.resolveArtworkURL(for: track, in: storageURL)
        }
        adapter.bind(controller: playback, engine: engine)
        nowPlayingAdapter = adapter
        #endif
    }

    var artworkLoader: ClassicArtworkLoader {
        { [repository] track in
            try? await repository.artworkData(for: track)
        }
    }

    var deviceNameProvider: @MainActor () -> String {
        { PlayerDeviceNameResolver.currentDisplayName() }
    }
}

#if DEBUG
private enum UITestLibraryFixture {
    private static let rootName = "VIPOD-UITesting"
    private static let fixtureArgument = "--uitesting-library-fixture"
    private static let resetArgument = "--uitesting-reset-library"
    private static let longListArgument = "--uitesting-long-list-fixture"
    private static let longCollectionArgument = "--uitesting-long-collection-fixture"

    static func storageURLIfRequested() throws -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(fixtureArgument) else { return nil }
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw RepositoryError.storageUnavailable
        }
        let root = support.appendingPathComponent(rootName, isDirectory: true).standardizedFileURL
        guard root.lastPathComponent == rootName, root.deletingLastPathComponent() == support.standardizedFileURL else {
            throw RepositoryError.storageUnavailable
        }
        if arguments.contains(resetArgument), FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Audio", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Artwork", isDirectory: true), withIntermediateDirectories: true)
        let catalogURL = root.appendingPathComponent("tracks.json")
        guard !FileManager.default.fileExists(atPath: catalogURL.path) else { return root }
        let tracks: [Track]
        let usesLongFixture = arguments.contains(longListArgument) || arguments.contains(longCollectionArgument)
        if usesLongFixture {
            tracks = (1...60).map { index in
                let suffix = String(format: "%012d", index)
                let id = UUID(uuidString: "BBBBBBBB-0000-0000-0000-\(suffix)")!
                return Track(id: id, title: String(format: "Long Song %02d", index), artist: "Fixture", album: "Long List", trackNumber: index, duration: 32, audioFilename: "long-\(index).mp3")
            }
        } else {
            tracks = [
            Track(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!, title: "Alpha", artist: "Fixture", album: "Queue", albumArtist: "Fixture", trackNumber: 1, discNumber: 1, duration: 32, audioFilename: "alpha.wav"),
            Track(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!, title: "Beta", artist: "Fixture", album: "Queue", albumArtist: "Fixture", trackNumber: 2, discNumber: 1, duration: 32, audioFilename: "beta.wav"),
            Track(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000003")!, title: "Gamma", artist: "Fixture", album: "Queue", albumArtist: "Fixture", trackNumber: 3, discNumber: 1, duration: 32, audioFilename: "gamma.wav")
            ]
            for track in tracks { try writeWaveFile(root.appendingPathComponent("Audio").appendingPathComponent(track.audioFilename)) }
        }
        try JSONEncoder().encode(tracks).write(to: catalogURL, options: .atomic)
        if arguments.contains(longCollectionArgument) {
            let playlistID = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!
            let catalog = LibraryCollectionCatalog(
                playlists: [LibraryPlaylist(id: playlistID, name: "Long Collection", trackIDs: tracks.map(\.id))],
                favoriteTrackIDs: Set(tracks.map(\.id))
            )
            let collectionsURL = root.appendingPathComponent("library-collections.json")
            try JSONEncoder().encode(catalog).write(to: collectionsURL, options: .atomic)
        }
        let session = PlaybackSession(revision: 1, selectedTrackID: usesLongFixture ? nil : tracks[0].id, elapsed: 0,
            queueIDs: tracks.map(\.id), shuffledIDs: tracks.map(\.id), repeatMode: .off, isShuffled: false)
        try JSONEncoder().encode(session).write(to: root.appendingPathComponent("playback-session.json"), options: .atomic)
        return root
    }

    private static func writeWaveFile(_ url: URL) throws {
        let sampleRate: UInt32 = 44_100
        let sampleCount = Int(sampleRate) * 32
        let dataSize = UInt32(sampleCount * 2)
        var data = Data("RIFF".utf8)
        data.appendLE(dataSize + 36)
        data.append(Data("WAVEfmt ".utf8))
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(1))
        data.appendLE(sampleRate)
        data.appendLE(sampleRate * 2)
        data.appendLE(UInt16(2))
        data.appendLE(UInt16(16))
        data.append(Data("data".utf8))
        data.appendLE(dataSize)
        for sample in 0..<sampleCount {
            let value = Int16(sin(Double(sample) * 2 * .pi * 220 / Double(sampleRate)) * 1_500)
            data.appendLE(UInt16(bitPattern: value))
        }
        try data.write(to: url, options: .atomic)
    }
}
#else
private enum UITestLibraryFixture {
    static func storageURLIfRequested() throws -> URL? { nil }
}
#endif

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

/// State owned by the app root so successful dependencies survive view reconstruction.
@MainActor
@Observable
final class AppComposition {
    private(set) var dependencies: AppDependencies?
    private(set) var didFailToStart = false

    init() {
        retryStartup()
    }

    func retryStartup() {
        do {
            dependencies = try AppDependencies()
            didFailToStart = false
        } catch {
            dependencies = nil
            didFailToStart = true
        }
    }
}
