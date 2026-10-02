import Foundation

public enum RepeatMode: String, Codable, Sendable { case off, all, one }

public struct PlaybackQueue: Sendable {
    public private(set) var tracks: [Track]
    public private(set) var currentIndex: Int?
    public private(set) var repeatMode: RepeatMode = .off
    public private(set) var isShuffled = false
    private var shuffledIDs: [UUID] = []

    public init(tracks: [Track] = []) { self.tracks = Self.uniqueTracks(tracks) }
    public var currentTrack: Track? { currentIndex.flatMap { tracks.indices.contains($0) ? tracks[$0] : nil } }
    public var orderedTracks: [Track] {
        guard isShuffled else { return Self.uniqueTracks(tracks) }
        var seen = Set<UUID>()
        let byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = shuffledIDs.compactMap { id -> Track? in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        }
        let missing = tracks.filter { seen.insert($0.id).inserted }
        return ordered + missing
    }

    public mutating func replaceTracks(_ tracks: [Track]) {
        let currentID = currentTrack?.id
        self.tracks = Self.uniqueTracks(tracks)
        currentIndex = currentID.flatMap { id in self.tracks.firstIndex { $0.id == id } }
        normalizeShuffleOrder()
    }
    public mutating func select(id: UUID) -> Track? {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return nil }
        currentIndex = index
        return tracks[index]
    }
    public mutating func setRepeatMode(_ mode: RepeatMode) { repeatMode = mode }
    public mutating func setShuffle(_ enabled: Bool, orderedIDs: [UUID]) {
        isShuffled = enabled
        shuffledIDs = enabled ? orderedIDs : []
        normalizeShuffleOrder()
    }
    public mutating func remove(id: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        let wasCurrent = currentIndex == index
        tracks.remove(at: index)
        shuffledIDs.removeAll { $0 == id }
        if tracks.isEmpty || wasCurrent { currentIndex = nil }
        else if let currentIndex, index < currentIndex { self.currentIndex = currentIndex - 1 }
    }
    public mutating func next(automatically: Bool = false) -> Track? {
        guard !tracks.isEmpty else { currentIndex = nil; return nil }
        if automatically, repeatMode == .one, let currentTrack { return currentTrack }
        let order = orderedTracks
        guard let currentTrack, let index = order.firstIndex(where: { $0.id == currentTrack.id }) else { return select(id: order[0].id) }
        if index + 1 < order.count { return select(id: order[index + 1].id) }
        guard repeatMode == .all else { return nil }
        return select(id: order[0].id)
    }
    public mutating func previous() -> Track? {
        guard !tracks.isEmpty else { currentIndex = nil; return nil }
        let order = orderedTracks
        guard let currentTrack, let index = order.firstIndex(where: { $0.id == currentTrack.id }) else { return select(id: order[0].id) }
        if index > 0 { return select(id: order[index - 1].id) }
        guard repeatMode == .all else { return nil }
        return select(id: order[order.count - 1].id)
    }

    private mutating func normalizeShuffleOrder() {
        guard isShuffled else { return }
        var seen = Set<UUID>()
        shuffledIDs = shuffledIDs.filter { id in
            tracks.contains { $0.id == id } && seen.insert(id).inserted
        }
        shuffledIDs += tracks.map(\.id).filter { seen.insert($0).inserted }
    }

    private static func uniqueTracks(_ tracks: [Track]) -> [Track] {
        var seen = Set<UUID>()
        return tracks.filter { seen.insert($0.id).inserted }
    }
}
