import Foundation

public protocol TrackRepository: Sendable {
    func tracks() async throws -> [Track]
    func importTracks(from urls: [URL]) async throws -> TrackImportReport
    func removeTrack(id: UUID) async throws
}

public struct TrackImportReport: Sendable {
    public let imported: [Track]
    public let failures: [TrackImportFailure]
    public let wasCancelled: Bool

    public init(imported: [Track], failures: [TrackImportFailure] = [], wasCancelled: Bool = false) {
        self.imported = imported
        self.failures = failures
        self.wasCancelled = wasCancelled
    }
}

public struct TrackImportFailure: Sendable, Identifiable {
    public enum Reason: Sendable, Equatable {
        case duplicate
        case unsupportedFormat
        case invalidAudio
        case other
    }

    public let id: UUID
    public let filename: String
    public let message: String
    public let reason: Reason

    public init(id: UUID = UUID(), filename: String, message: String, reason: Reason = .other) {
        self.id = id
        self.filename = filename
        self.message = message
        self.reason = reason
    }
}
