import Foundation

public enum AudioPlaybackStatus: Sendable, Equatable { case idle, ready, playing, paused, interrupted, failed(String) }
public enum AudioPlaybackEvent: Sendable { case completed, interrupted(shouldResume: Bool), routeDisconnected }

@MainActor public protocol AudioPlayback: AnyObject {
    var status: AudioPlaybackStatus { get }
    var elapsed: TimeInterval { get }
    var duration: TimeInterval { get }
    var onEvent: (@MainActor (AudioPlaybackEvent) -> Void)? { get set }
    var onStateChange: (@MainActor () -> Void)? { get set }
    func load(_ track: Track) throws
    func play() throws
    func pause()
    func seek(to seconds: TimeInterval) throws
    func stop()
}
