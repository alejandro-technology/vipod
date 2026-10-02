import Foundation

#if canImport(MediaPlayer) && os(iOS)
import MediaPlayer
import UIKit

@MainActor
public final class MediaPlayerNowPlayingAdapter {
    private weak var controller: PlaybackController?
    private weak var engine: AVFoundationAudioPlayback?
    private let artworkURLResolver: @Sendable (Track) throws -> URL?
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var cachedArtworkKey: ArtworkCacheKey?
    private var cachedArtwork: MPMediaItemArtwork?
    private var isBound = false

    public init(artworkURLResolver: @escaping @Sendable (Track) throws -> URL?) {
        self.artworkURLResolver = artworkURLResolver
    }

    public func bind(controller: PlaybackController, engine: AVFoundationAudioPlayback) {
        unbind()
        self.controller = controller
        self.engine = engine
        engine.onNowPlayingChange = { [weak self] in self?.refresh() }
        installCommands()
        isBound = true
        refresh()
    }

    public func unbind() {
        guard isBound else { return }
        commandTargets.forEach { $0.0.removeTarget($0.1) }
        commandTargets.removeAll()
        if let engine { engine.onNowPlayingChange = nil }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        cachedArtworkKey = nil
        cachedArtwork = nil
        controller = nil
        engine = nil
        isBound = false
        updateCommandAvailability()
    }

    private func installCommands() {
        let center = MPRemoteCommandCenter.shared()
        add(center.playCommand) { [weak self] _ in
            guard let self, self.controller?.currentTrack != nil else { return .noSuchContent }
            self.controller?.play()
            return self.isFailed ? .commandFailed : .success
        }
        add(center.pauseCommand) { [weak self] _ in
            guard let self, self.controller?.currentTrack != nil else { return .noSuchContent }
            self.controller?.pause()
            return self.isFailed ? .commandFailed : .success
        }
        add(center.togglePlayPauseCommand) { [weak self] _ in
            guard let self, let controller = self.controller, controller.currentTrack != nil else { return .noSuchContent }
            if case .playing = controller.status { controller.pause() } else { controller.play() }
            return self.isFailed ? .commandFailed : .success
        }
        add(center.nextTrackCommand) { [weak self] _ in
            guard let self, let controller = self.controller, controller.queue.orderedTracks.count > 1 else { return .noSuchContent }
            controller.next()
            return self.isFailed ? .commandFailed : .success
        }
        add(center.previousTrackCommand) { [weak self] _ in
            guard let self, let controller = self.controller, controller.currentTrack != nil else { return .noSuchContent }
            controller.previous()
            return self.isFailed ? .commandFailed : .success
        }
        add(center.changePlaybackPositionCommand) { [weak self] event in
            guard let self, let controller = self.controller,
                  let event = event as? MPChangePlaybackPositionCommandEvent,
                  controller.currentTrack != nil, controller.duration.isFinite, controller.duration > 0,
                  event.positionTime.isFinite else { return .noSuchContent }
            controller.seek(to: event.positionTime)
            return self.isFailed ? .commandFailed : .success
        }
    }

    private func add(_ command: MPRemoteCommand, handler: @escaping @MainActor (MPRemoteCommandEvent?) -> MPRemoteCommandHandlerStatus) {
        let target = command.addTarget { event in
            if Thread.isMainThread {
                return MainActor.assumeIsolated { handler(event) }
            }
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated { handler(event) }
            }
        }
        commandTargets.append((command, target))
        command.isEnabled = true
    }

    private var isFailed: Bool {
        guard let status = controller?.status else { return true }
        if case .failed = status { return true }
        return false
    }

    private func refresh() {
        guard let controller, let engine else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            updateCommandAvailability()
            return
        }
        guard let track = controller.currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            updateCommandAvailability()
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: engine.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: engine.status == .playing ? 1.0 : 0.0
        ]
        if engine.duration.isFinite, engine.duration >= 0 {
            info[MPMediaItemPropertyPlaybackDuration] = engine.duration
        }
        let artworkKey = track.artworkFilename.map { ArtworkCacheKey(trackID: track.id, filename: $0) }
        if artworkKey != cachedArtworkKey {
            cachedArtworkKey = artworkKey
            cachedArtwork = nil
            if let artworkURL = try? artworkURLResolver(track),
               let image = UIImage(contentsOfFile: artworkURL.path) {
                cachedArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
        }
        if let cachedArtwork { info[MPMediaItemPropertyArtwork] = cachedArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateCommandAvailability()
    }

    private func updateCommandAvailability() {
        guard let controller else {
            MPRemoteCommandCenter.shared().playCommand.isEnabled = false
            MPRemoteCommandCenter.shared().pauseCommand.isEnabled = false
            MPRemoteCommandCenter.shared().togglePlayPauseCommand.isEnabled = false
            MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = false
            MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = false
            MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = false
            return
        }
        let hasTrack = controller.currentTrack != nil
        let canAdvance = hasTrack && controller.queue.orderedTracks.count > 1
        let canSeek = hasTrack && controller.duration.isFinite && controller.duration > 0
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = hasTrack
        center.pauseCommand.isEnabled = hasTrack
        center.togglePlayPauseCommand.isEnabled = hasTrack
        center.nextTrackCommand.isEnabled = canAdvance
        center.previousTrackCommand.isEnabled = hasTrack
        center.changePlaybackPositionCommand.isEnabled = canSeek
    }
}

private struct ArtworkCacheKey: Equatable {
    let trackID: UUID
    let filename: String
}
#endif
