import Foundation
import Observation

/// View-facing menu, filtering, and playback-intent model over injected controllers.
@MainActor @Observable
public final class ClassicPlayerModel {
    public let library: LibraryController
    public let playback: PlaybackController
    public let collections: LibraryCollectionController
    public let audioConnection: AudioConnectionMonitor?
    public var deviceName: String
    public var navigation = PlayerNavigationState()
    public var selectedIndex = 0
    public var selectedQueueTrackID: UUID?
    public var filterText = ""
    public var isImporterPresented = false
    public var isSeeking = false
    public private(set) var selectedTrackForRemoval: Track?
    public private(set) var requestedTheme: PlayerThemeChoice?
    @ObservationIgnored private let operations: ClassicPlayerLibraryOperations
    @ObservationIgnored private let menuBuilder = ClassicPlayerMenuBuilder()

    public var importSummary: String? {
        get { operations.importSummary }
        set { operations.importSummary = newValue }
    }
    public var importFailures: [String] {
        get { operations.importFailures }
        set { operations.importFailures = newValue }
    }
    public var presentationError: String? {
        get { operations.presentationError }
        set { operations.presentationError = newValue }
    }
    public var loadFailed: Bool { operations.loadFailed }

    public init(library: LibraryController, playback: PlaybackController, collections: LibraryCollectionController? = nil, audioConnection: AudioConnectionMonitor? = nil, deviceName: String = String(localized: "iPod")) {
        self.library = library
        self.playback = playback
        let collections = collections ?? LibraryCollectionController(store: InMemoryLibraryCollectionStore(), tracks: library.tracks)
        self.collections = collections
        self.audioConnection = audioConnection
        self.deviceName = PlayerDeviceNameResolver.displayName(from: deviceName)
        self.operations = ClassicPlayerLibraryOperations(library: library, playback: playback, collections: collections)
    }

    // View teardown requires no actor-isolated work; avoid the same simulator
    // runtime deinit path as the library and playback controllers.
    nonisolated deinit {}

    public var rows: [ClassicPlayerRow] {
        let base = menuBuilder.rows(
            for: navigation.currentDestination,
            tracks: library.tracks,
            filterText: filterText,
            hasConnectedAudioOutput: audioConnection?.output != nil,
            deviceName: deviceName
        )
        switch navigation.currentDestination {
        case .playlistSongPicker(let playlistID):
            let playlistTrackIDs = Set(collections.catalog.playlists.first(where: { $0.id == playlistID })?.trackIDs ?? [])
            return library.tracks.filter { !playlistTrackIDs.contains($0.id) }.map { track in
                ClassicPlayerRow(id: "playlist.picker.\(track.id.uuidString)", title: track.title, subtitle: track.artist, action: .addToPlaylist(track, playlistID: playlistID))
            }
        case .playlists:
            return collections.catalog.playlists.map { playlist in
                ClassicPlayerRow(id: "playlist.\(playlist.id.uuidString)", title: playlist.name, subtitle: "\(playlist.trackIDs.count)", action: .open(.playlist(id: playlist.id)))
            }
        case .favorites:
            let favorites = library.tracks.filter { collections.catalog.favoriteTrackIDs.contains($0.id) }
            return favorites.map { ClassicPlayerRow(id: "track.\($0.id.uuidString)", title: $0.title, subtitle: $0.artist, action: .play($0, queue: favorites)) }
        case .playlist(let id):
            guard let playlist = collections.catalog.playlists.first(where: { $0.id == id }) else { return [] }
            let byID = Dictionary(library.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let ordered = playlist.trackIDs.compactMap { byID[$0] }
            return ordered.map { ClassicPlayerRow(id: "track.\($0.id.uuidString)", title: $0.title, subtitle: $0.artist, action: .play($0, queue: ordered)) }
        default: return base
        }
    }

    public var selectedRow: ClassicPlayerRow? {
        let currentRows = rows
        guard !currentRows.isEmpty else { return nil }
        return currentRows[min(max(selectedIndex, 0), currentRows.count - 1)]
    }

    public var selectedRowID: String? { selectedRow?.id }

    public var canRemoveSelectedTrack: Bool {
        removableSelectedTrack != nil
    }

    public func requestSelectedTrackRemoval() {
        guard let track = removableSelectedTrack else { return }
        selectedTrackForRemoval = track
    }

    public func cancelTrackRemoval() { selectedTrackForRemoval = nil }

    public func removeTrack(_ track: Track) async {
        guard !library.isLoading, !library.isImporting, !library.isRemoving else { return }
        let removed = await operations.removeTrack(track)
        if removed {
            normalizeSelection()
        }
        selectedTrackForRemoval = nil
    }

    public var screenTitle: String {
        switch navigation.currentDestination {
        case .mainMenu: deviceName
        case .music: String(localized: "Music")
        case .playlists: String(localized: "Playlists")
        case .playlist(let id): collections.catalog.playlists.first(where: { $0.id == id })?.name ?? String(localized: "Playlist")
        case .playlistSongPicker: String(localized: "Add Songs")
        case .favorites: String(localized: "Favorites")
        case .artists: String(localized: "Artists")
        case .artist(let name): name
        case .artistAlbums: String(localized: "Albums")
        case .artistSongs: String(localized: "Songs")
        case .artistAlbum(_, _, let title): title
        case .albums: String(localized: "Albums")
        case .album(_, let title): title
        case .songs: String(localized: "Songs")
        case .queue: String(localized: "Queue")
        case .nowPlaying: String(localized: "Now Playing")
        case .settings: String(localized: "Settings")
        }
    }

    public var playbackStatusText: String {
        switch playback.status {
        case .playing: String(localized: "Playing")
        case .paused: String(localized: "Paused")
        case .ready: String(localized: "Ready")
        case .interrupted: String(localized: "Interrupted")
        case .failed: String(localized: "Playback Error")
        case .idle: String(localized: "Stopped")
        }
    }

    public var currentTrackDurationText: String {
        let playbackDuration = playback.duration
        if playbackDuration.isFinite, playbackDuration > 0 {
            return formattedTime(playbackDuration)
        }
        if let trackDuration = playback.currentTrack?.duration,
           trackDuration.isFinite, trackDuration > 0 {
            return formattedTime(trackDuration)
        }
        return "--:--"
    }

    public var shouldShowEmptyLibrary: Bool {
        library.tracks.isEmpty && !library.isLoading && ![PlayerDestination.mainMenu, .settings, .nowPlaying].contains(navigation.currentDestination)
    }

    public func start() async {
        await operations.start()
    }

    public func retryLoad() async {
        await operations.retryLoad()
    }

    public func consumeRequestedTheme() -> PlayerThemeChoice? {
        defer { requestedTheme = nil }
        return requestedTheme
    }

    public func browse(by delta: Int) {
        if navigation.currentDestination == .queue {
            let tracks = playback.queue.orderedTracks
            guard !tracks.isEmpty else { return }
            let currentIndex = selectedQueueTrackID.flatMap { id in tracks.firstIndex(where: { $0.id == id }) } ?? 0
            selectedQueueTrackID = tracks[min(max(currentIndex + delta, 0), tracks.count - 1)].id
            return
        }
        let currentRows = rows
        guard !currentRows.isEmpty else {
            if navigation.currentDestination == .nowPlaying, isSeeking {
                let adjustment = max(playback.duration * 0.01, 5) * Double(delta)
                playback.seek(to: playback.elapsed + adjustment)
            }
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), currentRows.count - 1)
        if currentRows.indices.contains(selectedIndex) { navigation.select(itemID: currentRows[selectedIndex].id) }
    }

    public func normalizeSelection() {
        let currentRows = rows
        if let selection = navigation.selection, case .item(let id) = selection,
           let index = currentRows.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        } else {
            selectedIndex = currentRows.isEmpty ? 0 : min(max(selectedIndex, 0), currentRows.count - 1)
            if currentRows.indices.contains(selectedIndex) {
                navigation.select(itemID: currentRows[selectedIndex].id)
            } else {
                navigation.clearSelection()
            }
        }
    }

    public func nextPressed() {
        if playback.currentTrack != nil { playback.next() }
        else { browse(by: 1) }
    }

    public func previousPressed() {
        if playback.currentTrack != nil { playback.previous() }
        else { browse(by: -1) }
    }

    public func selectCurrent() {
        guard let selectedRow else { return }
        navigation.select(itemID: selectedRow.id)
        perform(selectedRow.action)
    }

    public func activate(_ row: ClassicPlayerRow) {
        let currentRows = rows
        if let index = currentRows.firstIndex(where: { $0.id == row.id }) { selectedIndex = index }
        navigation.select(itemID: row.id)
        perform(row.action)
    }

    public func menuPressed() {
        if isSeeking { isSeeking = false; return }
        _ = navigation.pop()
        resetSelection()
    }

    public func selectPressed() {
        if navigation.currentDestination == .queue { playSelectedQueueTrack(); return }
        if navigation.currentDestination == .nowPlaying { isSeeking.toggle() }
        else { selectCurrent() }
    }

    public func togglePlayback() {
        if playback.status == .playing { playback.pause() }
        else if playback.currentTrack == nil, let first = library.tracks.first {
            playback.replaceQueue(with: library.tracks)
            playback.play(first)
        } else if playback.currentTrack == nil {
            presentationError = String(localized: "Import or select a song before starting playback.")
        } else {
            playback.play()
        }
    }

    public func importFiles(from urls: [URL]) async {
        await operations.importFiles(from: urls)
    }

    public func importerCancelled() {
        operations.importerCancelled()
    }

    public func importerFailed() {
        operations.importerFailed()
    }

    public func setRepeat(_ mode: RepeatMode) { playback.setRepeatMode(mode) }

    public func toggleShuffle() { playback.toggleShuffle() }

    public func openQueue() {
        selectedQueueTrackID = playback.currentTrack?.id ?? playback.queue.orderedTracks.first?.id
        navigation.push(.queue)
    }

    public func openPlaylistSongPicker(for playlistID: UUID) {
        guard navigation.currentDestination == .playlist(id: playlistID) else { return }
        filterText = ""
        navigation.push(.playlistSongPicker(id: playlistID))
        selectedIndex = 0
        resetSelection()
    }

    public func playNext(_ track: Track) { playback.playNext(track) }

    public func addLast(_ track: Track) { playback.addLast(track) }

    public func createPlaylist(named name: String) async -> UUID? {
        let id = await collections.createPlaylist(named: name)
        presentationError = collections.errorMessage
        normalizeSelection()
        return id
    }
    public func renamePlaylist(id: UUID, to name: String) async {
        await collections.renamePlaylist(id: id, to: name)
        presentationError = collections.errorMessage
        normalizeSelection()
    }
    public func deletePlaylist(id: UUID) async {
        await collections.deletePlaylist(id: id)
        presentationError = collections.errorMessage
        normalizeSelection()
    }
    public func addToPlaylist(_ trackID: UUID, playlistID: UUID) async {
        await collections.addTrack(trackID, toPlaylist: playlistID)
        presentationError = collections.errorMessage
        normalizeSelection()
    }
    public func removeFromPlaylist(_ trackID: UUID, playlistID: UUID) async {
        await collections.removeTrack(trackID, fromPlaylist: playlistID)
        presentationError = collections.errorMessage
        normalizeSelection()
    }
    public func toggleFavorite(_ trackID: UUID) async {
        await collections.toggleFavorite(trackID)
        presentationError = collections.errorMessage
        normalizeSelection()
    }
    public func movePlaylistTrack(playlistID: UUID, trackID: UUID, by offset: Int) async {
        await collections.moveTrack(trackID, inPlaylist: playlistID, by: offset)
        presentationError = collections.errorMessage
        normalizeSelection()
    }
    public func playCollection(_ ids: [UUID]) {
        let byID = Dictionary(library.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = ids.compactMap { byID[$0] }
        guard let first = ordered.first else { return }
        if playback.isShuffled { playback.toggleShuffle() }
        playback.replaceQueue(with: ordered)
        playback.play(first)
        navigation.push(.nowPlaying)
    }

    public func selectQueueTrack(_ id: UUID) { selectedQueueTrackID = id }

    public func moveSelectedQueueTrack(by delta: Int) {
        guard let id = selectedQueueTrackID,
              let index = playback.queue.orderedTracks.firstIndex(where: { $0.id == id }) else { return }
        playback.moveQueueItem(id: id, to: index + delta)
    }

    public func removeSelectedQueueTrack() {
        let tracks = playback.queue.orderedTracks
        guard let id = selectedQueueTrackID, let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        playback.removeTrack(id: id)
        if !playback.queue.orderedTracks.contains(where: { $0.id == id }) {
            let remaining = playback.queue.orderedTracks
            selectedQueueTrackID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
    }

    public func removeQueueTrack(id: UUID) { playback.removeTrack(id: id) }

    public func playSelectedQueueTrack() {
        guard let id = selectedQueueTrackID,
              let track = playback.queue.orderedTracks.first(where: { $0.id == id }) else { return }
        playback.play(track)
    }

    public func formattedTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time < Double(Int.max) else { return "--:--" }
        let seconds = Int(max(0, time))
        let remainder = seconds % 60
        let paddedRemainder = remainder < 10 ? "0\(remainder)" : "\(remainder)"
        return "\(seconds / 60):\(paddedRemainder)"
    }

    private func perform(_ action: ClassicPlayerRow.Action) {
        switch action {
        case .open(let destination):
            if destination == .queue {
                selectedQueueTrackID = playback.currentTrack?.id ?? playback.queue.orderedTracks.first?.id
            }
            navigation.push(destination)
            isSeeking = false
            filterText = ""
            resetSelection()
        case .play(let track, let queue):
            if case .playlist = navigation.currentDestination, playback.isShuffled {
                playback.toggleShuffle()
            }
            playback.replaceQueue(with: queue)
            playback.play(track)
            navigation.push(.nowPlaying)
            resetSelection()
        case .addToPlaylist(let track, let playlistID):
            Task { await addToPlaylist(track.id, playlistID: playlistID) }
        case .shuffle(let tracks):
            guard !tracks.isEmpty else { return }
            playback.replaceQueue(with: tracks)
            if playback.isShuffled { playback.toggleShuffle() }
            playback.toggleShuffle()
            playback.play(playback.queue.orderedTracks.first)
            navigation.push(.nowPlaying)
            resetSelection()
        case .importMusic:
            guard !library.isImporting else { return }
            isImporterPresented = true
        case .setTheme(let theme):
            requestedTheme = theme
        case .setRepeat(let mode):
            playback.setRepeatMode(mode)
        case .setBluetoothKind(let kind):
            audioConnection?.setPreferredDeviceKind(kind)
        case .toggleShuffle:
            playback.toggleShuffle()
        }
    }

    private func resetSelection() {
        selectedIndex = 0
        if let first = rows.first { navigation.select(itemID: first.id) }
        else { navigation.clearSelection() }
    }

    private var removableSelectedTrack: Track? {
        guard navigation.currentDestination == .songs,
              !library.isLoading, !library.isImporting, !library.isRemoving,
              let selectedRow,
              case .play(let track, _) = selectedRow.action,
              library.tracks.contains(where: { $0.id == track.id }) else { return nil }
        return track
    }

    public var selectedSongTrack: Track? {
        guard let selectedRow, case .play(let track, _) = selectedRow.action else { return nil }
        return track
    }

    public var isSelectedTrackFavorite: Bool {
        guard let track = selectedSongTrack else { return false }
        return collections.catalog.favoriteTrackIDs.contains(track.id)
    }

    public var shouldShowSongActions: Bool {
        navigation.currentDestination == .songs || selectedSongTrack != nil
    }

    public func selectRow(_ row: ClassicPlayerRow) {
        let currentRows = rows
        if let index = currentRows.firstIndex(where: { $0.id == row.id }) {
            selectedIndex = index
            navigation.select(itemID: row.id)
        }
    }
}

private actor InMemoryLibraryCollectionStore: LibraryCollectionStore {
    private var catalog = LibraryCollectionCatalog()
    func load() async throws -> LibraryCollectionCatalog { catalog }
    func save(_ catalog: LibraryCollectionCatalog) async throws { self.catalog = catalog }
}
