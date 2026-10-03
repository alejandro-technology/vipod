import Foundation

nonisolated public struct PlaybackSession: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let selectedTrackID: UUID?
    public let elapsed: TimeInterval
    public let queueIDs: [UUID]
    public let shuffledIDs: [UUID]
    public let repeatMode: RepeatMode
    public let isShuffled: Bool

    public init(revision: UInt64 = 0, selectedTrackID: UUID?, elapsed: TimeInterval, queueIDs: [UUID], shuffledIDs: [UUID], repeatMode: RepeatMode, isShuffled: Bool) {
        self.revision = revision
        self.selectedTrackID = selectedTrackID
        self.elapsed = elapsed
        self.queueIDs = queueIDs
        self.shuffledIDs = shuffledIDs
        self.repeatMode = repeatMode
        self.isShuffled = isShuffled
    }
}

nonisolated public protocol PlaybackSessionStore: Sendable {
    func load() async -> PlaybackSession?
    func save(_ session: PlaybackSession) async
}
