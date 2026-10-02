import AVFoundation
import Foundation

@MainActor
public final class AVFoundationAudioPlayback: NSObject, AudioPlayback, AVAudioPlayerDelegate {
    public private(set) var status: AudioPlaybackStatus = .idle
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public var onEvent: (@MainActor (AudioPlaybackEvent) -> Void)?
    public var onStateChange: (@MainActor () -> Void)?
    public var onNowPlayingChange: (@MainActor () -> Void)?

    private let mediaURLResolver: @Sendable (Track) throws -> URL
    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    public init(mediaURLResolver: @escaping @Sendable (Track) throws -> URL) {
        self.mediaURLResolver = mediaURLResolver
        super.init()
        installSessionObservers()
    }

    deinit {
        progressTimer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    public func load(_ track: Track) throws {
        stopTimer()
        player?.stop()
        player = nil
        do {
            let url = try mediaURLResolver(track)
            let next = try AVAudioPlayer(contentsOf: url)
            guard next.duration.isFinite, next.duration >= 0 else { throw PlaybackError.invalidDuration }
            next.delegate = self
            guard next.prepareToPlay() else { throw PlaybackError.couldNotPrepare }
            player = next
            elapsed = 0
            duration = next.duration
            status = .ready
            publishChange()
        } catch {
            setFailure(error)
            throw error
        }
    }

    public func play() throws {
        guard let player else { throw PlaybackError.noTrackLoaded }
        do {
            #if os(iOS) || os(visionOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            guard player.play() else { throw PlaybackError.couldNotStart }
            status = .playing
            startTimer()
            publishChange()
        } catch {
            setFailure(error)
            throw error
        }
    }

    public func pause() {
        guard let player else { return }
        player.pause()
        elapsed = player.currentTime
        status = .paused
        stopTimer()
        deactivateSessionIfSafe()
        publishChange()
    }

    public func seek(to seconds: TimeInterval) throws {
        guard let player else { throw PlaybackError.noTrackLoaded }
        guard seconds.isFinite else { throw PlaybackError.invalidSeekPosition }
        player.currentTime = min(max(0, seconds), player.duration)
        elapsed = player.currentTime
        publishChange()
    }

    public func stop() {
        player?.stop()
        player = nil
        elapsed = 0
        duration = 0
        status = .idle
        stopTimer()
        deactivateSessionIfSafe()
        publishChange()
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.elapsed = self.duration
            self.stopTimer()
            if flag {
                self.status = .ready
                self.onEvent?(.completed)
                self.deactivateSessionIfSafe()
            } else {
                self.setFailure(PlaybackError.unexpectedEnd)
                return
            }
            self.publishChange()
        }
    }

    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = error?.localizedDescription ?? "The audio file could not be decoded."
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.setFailure(PlaybackError.decodeFailure(message))
        }
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player, self.status == .playing else { return }
                self.elapsed = player.currentTime.isFinite ? max(0, player.currentTime) : 0
                self.publishChange()
            }
        }
        progressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func publishChange() {
        onStateChange?()
        onNowPlayingChange?()
    }

    private func setFailure(_ error: Error) {
        player?.stop()
        player?.delegate = nil
        player = nil
        elapsed = 0
        duration = 0
        status = .failed(Self.userMessage(for: error))
        stopTimer()
        deactivateSessionIfSafe()
        publishChange()
    }

    private static func userMessage(for error: Error) -> String {
        if let error = error as? PlaybackError {
            switch error {
            case .noTrackLoaded: return "Choose a track before starting playback."
            case .invalidDuration, .couldNotPrepare, .couldNotStart, .invalidSeekPosition: return "The selected track could not be played."
            case .decodeFailure: return "The audio file could not be decoded."
            case .unexpectedEnd: return "Audio playback ended unexpectedly."
            }
        }
        return "The selected track is unavailable or could not be played."
    }

    private func installSessionObservers() {
        #if os(iOS) || os(visionOS)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch type {
                case .began:
                    self.player?.pause()
                    self.elapsed = self.player?.currentTime ?? self.elapsed
                    self.status = .interrupted
                    self.stopTimer()
                    self.publishChange()
                case .ended:
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                    self.status = .paused
                    self.publishChange()
                    self.onEvent?(.interrupted(shouldResume: options.contains(.shouldResume)))
                @unknown default: break
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor [weak self] in
                guard let self, self.status == .playing else { return }
                self.player?.pause()
                self.elapsed = self.player?.currentTime ?? self.elapsed
                self.status = .paused
                self.stopTimer()
                self.publishChange()
                self.onEvent?(.routeDisconnected)
            }
        })
        #endif
    }

    private func deactivateSessionIfSafe() {
        #if os(iOS) || os(visionOS)
        guard status != .playing else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

public enum PlaybackError: Error, Sendable {
    case noTrackLoaded
    case invalidDuration
    case couldNotPrepare
    case couldNotStart
    case invalidSeekPosition
    case decodeFailure(String)
    case unexpectedEnd
}
