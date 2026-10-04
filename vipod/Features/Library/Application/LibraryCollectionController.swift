import Foundation
import Observation

@MainActor @Observable
public final class LibraryCollectionController {
    public private(set) var catalog: LibraryCollectionCatalog
    public private(set) var errorMessage: String?
    public private(set) var hasLoaded: Bool

    public init(store: any LibraryCollectionStore, tracks: [Track] = [], catalog: LibraryCollectionCatalog? = nil) {
        self.store = store
        self.tracks = tracks
        self.catalog = catalog ?? .init()
        self.hasLoaded = catalog != nil
    }

    nonisolated deinit {}

    private let store: any LibraryCollectionStore
    private var tracks: [Track]
    private var mutationInProgress = false
    private var waitingMutations: [CheckedContinuation<Void, Never>] = []

    public func load() async {
        await acquireMutation()
        defer { releaseMutation() }
        _ = await loadCatalog()
    }

    // Called only while holding the mutation gate, including first-use commands.
    // A failed read never grants permission to overwrite the durable catalog.
    private func loadCatalog() async -> Bool {
        do {
            let loaded = try await store.load()
            let normalized = reconciled(loaded, validIDs: Set(tracks.map(\.id)))
            if normalized != loaded { try await store.save(normalized) }
            catalog = normalized
            hasLoaded = true
            errorMessage = nil
            return true
        } catch {
            hasLoaded = false
            errorMessage = "The playlists and favorites could not be loaded or saved."
            return false
        }
    }

    private func ensureLoaded() async -> Bool {
        if hasLoaded { return true }
        return await loadCatalog()
    }

    public func updateLibraryTracks(_ tracks: [Track]) async {
        // Announce the latest library before waiting for a suspended save.
        // Older queued reconciliation requests must not restore stale membership.
        self.tracks = tracks
        await acquireMutation()
        defer { releaseMutation() }
        guard hasLoaded else { return }
        _ = await commit(reconciled(catalog, validIDs: Set(self.tracks.map(\.id))))
    }

    @discardableResult public func createPlaylist(named name: String) async -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { errorMessage = "Playlist names cannot be blank."; return nil }
        await acquireMutation()
        defer { releaseMutation() }
        guard await ensureLoaded() else { return nil }
        let playlist = LibraryPlaylist(name: name)
        var next = catalog
        next.playlists.append(playlist)
        return await commit(next) ? playlist.id : nil
    }

    public func renamePlaylist(id: UUID, to name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { errorMessage = "Playlist names cannot be blank."; return }
        await acquireMutation()
        defer { releaseMutation() }
        guard await ensureLoaded() else { return }
        var next = catalog
        guard let index = next.playlists.firstIndex(where: { $0.id == id }) else { return }
        next.playlists[index].name = name
        _ = await commit(next)
    }

    public func deletePlaylist(id: UUID) async {
        await acquireMutation()
        defer { releaseMutation() }
        guard await ensureLoaded() else { return }
        var next = catalog
        next.playlists.removeAll { $0.id == id }
        _ = await commit(next)
    }

    public func addTrack(_ trackID: UUID, toPlaylist id: UUID) async {
        await acquireMutation()
        defer { releaseMutation() }
        guard await ensureLoaded() else { return }
        guard tracks.contains(where: { $0.id == trackID }) else { return }
        var next = catalog
        guard let index = next.playlists.firstIndex(where: { $0.id == id }) else { return }
        if !next.playlists[index].trackIDs.contains(trackID) { next.playlists[index].trackIDs.append(trackID) }
        _ = await commit(next)
    }

    public func removeTrack(_ trackID: UUID, fromPlaylist id: UUID) async {
        await acquireMutation()
        defer { releaseMutation() }
        guard await ensureLoaded() else { return }
        var next = catalog
        guard let index = next.playlists.firstIndex(where: { $0.id == id }) else { return }
        next.playlists[index].trackIDs.removeAll { $0 == trackID }
        _ = await commit(next)
    }

    public func reorderPlaylist(_ id: UUID, trackIDs: [UUID]) async {
        await acquireMutation()
        defer { releaseMutation() }
        guard await ensureLoaded() else { return }
        var next = catalog
        guard let index = next.playlists.firstIndex(where: { $0.id == id }) else { return }
        let existing = Set(next.playlists[index].trackIDs)
        var seen = Set<UUID>()
        let requested = trackIDs.filter { existing.contains($0) && seen.insert($0).inserted }
        let remainder = next.playlists[index].trackIDs.filter { seen.insert($0).inserted }
        next.playlists[index].trackIDs = requested + remainder
        _ = await commit(next)
    }

    public func moveTrack(_ trackID: UUID, inPlaylist id: UUID, by offset: Int) async {
        await acquireMutation()
        defer { releaseMutation() }
        guard await ensureLoaded() else { return }
        var next = catalog
        guard let playlistIndex = next.playlists.firstIndex(where: { $0.id == id }),
              let source = next.playlists[playlistIndex].trackIDs.firstIndex(of: trackID) else { return }
        let (requested, overflow) = source.addingReportingOverflow(offset)
        guard !overflow else { return }
        let target = min(max(requested, 0), next.playlists[playlistIndex].trackIDs.count - 1)
        let moved = next.playlists[playlistIndex].trackIDs.remove(at: source)
        next.playlists[playlistIndex].trackIDs.insert(moved, at: target)
        _ = await commit(next)
    }

    public func setFavorite(_ trackID: UUID, isFavorite: Bool) async {
        await changeFavorite(trackID, to: isFavorite)
    }

    public func toggleFavorite(_ trackID: UUID) async {
        await changeFavorite(trackID, to: nil)
    }

    private func changeFavorite(_ trackID: UUID, to requestedValue: Bool?) async {
        await acquireMutation()
        defer { releaseMutation() }
        guard await ensureLoaded() else { return }
        guard tracks.contains(where: { $0.id == trackID }) else { return }
        var next = catalog
        let isFavorite = requestedValue ?? !next.favoriteTrackIDs.contains(trackID)
        if isFavorite { next.favoriteTrackIDs.insert(trackID) }
        else { next.favoriteTrackIDs.remove(trackID) }
        _ = await commit(next)
    }

    private func commit(_ next: LibraryCollectionCatalog) async -> Bool {
        guard next != catalog else { return true }
        do {
            try await store.save(next)
            catalog = next
            errorMessage = nil
            return true
        } catch {
            errorMessage = "The playlists and favorites could not be saved."
            return false
        }
    }

    private func reconciled(_ catalog: LibraryCollectionCatalog, validIDs: Set<UUID>) -> LibraryCollectionCatalog {
        var result = catalog
        result.playlists = catalog.playlists.map { playlist in
            var seen = Set<UUID>()
            return LibraryPlaylist(id: playlist.id, name: playlist.name, trackIDs: playlist.trackIDs.filter { validIDs.contains($0) && seen.insert($0).inserted })
        }
        result.favoriteTrackIDs.formIntersection(validIDs)
        return result
    }

    private func acquireMutation() async {
        if mutationInProgress {
            await withCheckedContinuation { waitingMutations.append($0) }
        } else { mutationInProgress = true }
    }

    private func releaseMutation() {
        if waitingMutations.isEmpty { mutationInProgress = false }
        else { waitingMutations.removeFirst().resume() }
    }
}
