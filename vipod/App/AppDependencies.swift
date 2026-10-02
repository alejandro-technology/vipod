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
    let playback: PlaybackController
    let audioConnection: AudioConnectionMonitor

    #if canImport(MediaPlayer) && os(iOS)
    private let nowPlayingAdapter: MediaPlayerNowPlayingAdapter
    #endif

    init() throws {
        let repository = try FileTrackRepository()
        let storageURL = repository.storageURL
        let engine = AVFoundationAudioPlayback { track in
            try FileTrackRepository.resolveMediaURL(for: track, in: storageURL)
        }
        let library = LibraryController(repository: repository)
        let playback = PlaybackController(engine: engine)
        let audioConnection = AudioConnectionMonitor()

        self.repository = repository
        self.engine = engine
        self.library = library
        self.playback = playback
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
