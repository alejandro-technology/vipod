import Foundation

public actor FilePlaybackSessionStore: PlaybackSessionStore {
    private let url: URL
    private var latestRevision: UInt64?

    public init(url: URL) { self.url = url }

    public func load() async -> PlaybackSession? {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(PlaybackSession.self, from: data) else { return nil }
        latestRevision = max(latestRevision ?? value.revision, value.revision)
        return value
    }

    public func save(_ session: PlaybackSession) async {
        guard latestRevision.map({ session.revision > $0 }) ?? true,
              let data = try? JSONEncoder().encode(session) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            latestRevision = session.revision
        } catch {
            // Session persistence is best-effort and must not interrupt playback or library storage.
        }
    }
}
