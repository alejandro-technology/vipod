import Foundation

public enum RepeatMode: String, Codable, Sendable { case off, all, one }

public struct PlaybackQueue: Sendable {
    public private(set) var tracks: [Track]
    public private(set) var currentIndex: Int?
    public private(set) var repeatMode: RepeatMode = .off
    public private(set) var isShuffled = false
    private var shuffledIDs: [UUID] = []

    public init(tracks: [Track] = []) { self.tracks = Self.uniqueTracks(tracks) }
    public mutating func restore(tracks: [Track], selectedID: UUID?, repeatMode: RepeatMode, isShuffled: Bool, shuffledIDs: [UUID]) {
        self.tracks = Self.uniqueTracks(tracks)
        currentIndex = selectedID.flatMap { id in self.tracks.firstIndex { $0.id == id } }
        self.repeatMode = repeatMode
        self.isShuffled = isShuffled
        self.shuffledIDs = isShuffled ? shuffledIDs : []
        normalizeShuffleOrder()
    }
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
    @discardableResult
    public mutating func enqueueNext(_ track: Track) -> Bool {
        guard currentTrack?.id != track.id else { return false }
        var visible = orderedTracks
        visible.removeAll { $0.id == track.id }
        let insertionIndex: Int
        if let currentTrack, let currentIndex = visible.firstIndex(where: { $0.id == currentTrack.id }) {
            insertionIndex = currentIndex + 1
        } else {
            insertionIndex = 0
        }
        visible.insert(track, at: insertionIndex)
        setVisibleOrder(visible)
        return true
    }
    @discardableResult
    public mutating func addLast(_ track: Track) -> Bool {
        guard currentTrack?.id != track.id else { return false }
        var visible = orderedTracks
        visible.removeAll { $0.id == track.id }
        visible.append(track)
        setVisibleOrder(visible)
        return true
    }
    @discardableResult
    public mutating func move(id: UUID, toVisibleIndex index: Int) -> Bool {
        var visible = orderedTracks
        guard visible.indices.contains(index), let sourceIndex = visible.firstIndex(where: { $0.id == id }) else { return false }
        guard sourceIndex != index else { return true }
        let currentID = currentTrack?.id
        let track = visible.remove(at: sourceIndex)
        visible.insert(track, at: index)
        setVisibleOrder(visible, selectedID: currentID)
        return true
    }

    private mutating func setVisibleOrder(_ visible: [Track], selectedID: UUID? = nil) {
        let selectedID = selectedID ?? currentTrack?.id
        tracks = Self.uniqueTracks(visible)
        currentIndex = selectedID.flatMap { id in tracks.firstIndex(where: { $0.id == id }) }
        if isShuffled { shuffledIDs = tracks.map(\.id) }
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
