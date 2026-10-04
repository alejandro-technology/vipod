import Foundation

nonisolated public struct LibraryPlaylist: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var trackIDs: [UUID]

    public init(id: UUID = UUID(), name: String, trackIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
    }
}

nonisolated public struct LibraryCollectionCatalog: Codable, Equatable, Sendable {
    public var playlists: [LibraryPlaylist]
    public var favoriteTrackIDs: Set<UUID>

    public init(playlists: [LibraryPlaylist] = [], favoriteTrackIDs: Set<UUID> = []) {
        self.playlists = playlists
        self.favoriteTrackIDs = favoriteTrackIDs
    }
}

nonisolated public protocol LibraryCollectionStore: Sendable {
    func load() async throws -> LibraryCollectionCatalog
    func save(_ catalog: LibraryCollectionCatalog) async throws
}
