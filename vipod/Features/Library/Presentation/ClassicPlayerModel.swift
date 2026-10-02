import Foundation
import Observation

public enum PlayerThemeChoice: String, Hashable, Sendable {
    case black
    case white
}

private struct AlbumKey: Hashable {
    let artist: String
    let title: String

    var stableID: String {
        "album.\(artist.utf8.count):\(artist)\(title.utf8.count):\(title)"
    }
}

public struct ClassicPlayerRow: Identifiable, Sendable {
    public enum Action: Sendable {
        case open(PlayerDestination)
        case play(Track, queue: [Track])
        case shuffle([Track])
        case importMusic
        case setTheme(PlayerThemeChoice)
        case setRepeat(RepeatMode)
        case setBluetoothKind(BluetoothDeviceKind)
        case toggleShuffle
    }

    public let id: String
    public let title: String
    public let subtitle: String?
    public let action: Action

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        action: Action
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }
}

/// View-facing menu, filtering, and playback-intent model over injected controllers.
@MainActor @Observable
public final class ClassicPlayerModel {
    public let library: LibraryController
    public let playback: PlaybackController
    public let audioConnection: AudioConnectionMonitor?
    public var navigation = PlayerNavigationState()
    public var selectedIndex = 0
    public var filterText = ""
    public var isImporterPresented = false
    public var isSeeking = false
    public var importSummary: String?
    public var importFailures: [String] = []
    public var presentationError: String?
    public private(set) var selectedTrackForRemoval: Track?
    public private(set) var requestedTheme: PlayerThemeChoice?
    public private(set) var loadFailed = false

    @ObservationIgnored private var didStart = false

    public init(library: LibraryController, playback: PlaybackController, audioConnection: AudioConnectionMonitor? = nil) {
        self.library = library
        self.playback = playback
        self.audioConnection = audioConnection
    }

    // View teardown requires no actor-isolated work; avoid the same simulator
    // runtime deinit path as the library and playback controllers.
    nonisolated deinit {}

    public var rows: [ClassicPlayerRow] {
        switch navigation.currentDestination {
        case .mainMenu:
            return [
                row("menu.music", String(localized: "Music"), .open(.music)),
                row("menu.shuffle", String(localized: "Shuffle Songs"), .shuffle(library.tracks)),
                row("menu.nowPlaying", String(localized: "Now Playing"), .open(.nowPlaying)),
                row("menu.settings", String(localized: "Settings"), .open(.settings)),
                row("menu.import", String(localized: "Import Music"), .importMusic)
            ]
        case .music:
            return [
                row("music.artists", String(localized: "Artists"), .open(.artists)),
                row("music.albums", String(localized: "Albums"), .open(.albums)),
                row("music.songs", String(localized: "Songs"), .open(.songs)),
                row("menu.import", String(localized: "Import Music"), .importMusic)
            ]
        case .artists:
            return filtered(Array(Set(library.tracks.map(\.artist))).sorted().map { name in
                row("artist.\(name)", name, .open(.artist(name: name)))
            })
        case .artist(let name):
            let tracks = library.tracks.filter { $0.artist == name }
            let albums = albumKeys(in: tracks)
            return filtered(albums.map { album in
                row(album.stableID, album.title, .open(.album(artist: album.artist, title: album.title)))
            } + tracks.map { trackRow($0, queue: filteredTracks(tracks)) })
        case .albums:
            return filtered(albumKeys(in: library.tracks).map { album in
                row(album.stableID, album.title, .open(.album(artist: album.artist, title: album.title)), subtitle: album.artist)
            })
        case .album(let artist, let album):
            let tracks = library.tracks.filter { $0.artist == artist && $0.album == album }
            return filtered(tracks.map { trackRow($0, queue: filteredTracks(tracks)) })
        case .songs:
            return filtered(library.tracks.map { trackRow($0, queue: filteredTracks(library.tracks)) })
        case .nowPlaying:
            return []
        case .settings:
            var settingsRows: [ClassicPlayerRow] = [
                row("theme.black", String(localized: "Black iPod"), .setTheme(.black)),
                row("theme.white", String(localized: "White iPod"), .setTheme(.white)),
                row("settings.shuffle", String(localized: "Shuffle"), .toggleShuffle),
                row("repeat.off", String(localized: "Repeat Off"), .setRepeat(.off)),
                row("repeat.all", String(localized: "Repeat All"), .setRepeat(.all)),
                row("repeat.one", String(localized: "Repeat One"), .setRepeat(.one)),
                row("menu.import", String(localized: "Import Music"), .importMusic)
            ]
            if audioConnection?.output != nil {
                settingsRows.insert(contentsOf: BluetoothDeviceKind.allCases.map { kind in
                    row("settings.bluetooth.\(kind.rawValue)", bluetoothKindName(kind), .setBluetoothKind(kind))
                }, at: settingsRows.count - 1)
            }
            return settingsRows
        }
    }

    public var selectedRow: ClassicPlayerRow? {
        guard !rows.isEmpty else { return nil }
        return rows[min(max(selectedIndex, 0), rows.count - 1)]
    }

    public var selectedRowID: String? { selectedRow?.id }

    public var canRemoveSelectedTrack: Bool {
        guard navigation.currentDestination == .songs,
              !library.isLoading, !library.isImporting, !library.isRemoving,
              let selectedRow,
              case .play(let track, _) = selectedRow.action else { return false }
        return library.tracks.contains { $0.id == track.id }
    }

    public func requestSelectedTrackRemoval() {
        guard canRemoveSelectedTrack,
              let selectedRow,
              case .play(let track, _) = selectedRow.action else { return }
        selectedTrackForRemoval = track
    }

    public func cancelTrackRemoval() { selectedTrackForRemoval = nil }

    public func removeTrack(_ track: Track) async {
        guard !library.isLoading, !library.isImporting, !library.isRemoving else { return }
        presentationError = nil
        library.clearError()
        let removed = await library.removeTrack(id: track.id)
        if removed {
            playback.removeTrack(id: track.id)
            normalizeSelection()
        } else if let error = library.errorMessage {
            presentationError = error
        }
        selectedTrackForRemoval = nil
    }

    public var screenTitle: String {
        switch navigation.currentDestination {
        case .mainMenu: String(localized: "iPod")
        case .music: String(localized: "Music")
        case .artists: String(localized: "Artists")
        case .artist(let name): name
        case .albums: String(localized: "Albums")
        case .album(_, let title): title
        case .songs: String(localized: "Songs")
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
        guard !didStart else { return }
        didStart = true
        guard library.tracks.isEmpty else { return }
        await library.load()
        loadFailed = library.errorMessage != nil
    }

    public func retryLoad() async {
        guard !library.isLoading else { return }
        loadFailed = false
        await library.load()
        loadFailed = library.errorMessage != nil
    }

    public func consumeRequestedTheme() -> PlayerThemeChoice? {
        defer { requestedTheme = nil }
        return requestedTheme
    }

    public func browse(by delta: Int) {
        guard !rows.isEmpty else {
            if navigation.currentDestination == .nowPlaying, isSeeking {
                let adjustment = max(playback.duration * 0.01, 5) * Double(delta)
                playback.seek(to: playback.elapsed + adjustment)
            }
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), rows.count - 1)
    }

    public func normalizeSelection() {
        selectedIndex = rows.isEmpty ? 0 : min(max(selectedIndex, 0), rows.count - 1)
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
        if let index = rows.firstIndex(where: { $0.id == row.id }) { selectedIndex = index }
        navigation.select(itemID: row.id)
        perform(row.action)
    }

    public func menuPressed() {
        if isSeeking { isSeeking = false; return }
        _ = navigation.pop()
        resetSelection()
    }

    public func selectPressed() {
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
        guard !urls.isEmpty else { return }
        presentationError = nil
        let previousReport = library.lastImportReport
        library.clearError()
        let accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
        // The repository also acquires access while copying; keep every selected URL so it can report per-file failures.
        await library.importTracks(from: urls)
        if !library.tracks.isEmpty { loadFailed = false }
        if let report = library.lastImportReport, !sameReport(report, previousReport) {
            let count = report.imported.count
            importSummary = report.wasCancelled
                ? String(localized: "Import was cancelled.")
                : String.localizedStringWithFormat(String(localized: "%lld imported, %lld failed"), count, report.failures.count)
            importFailures = report.failures.map(\.filename)
        } else {
            importSummary = nil
            importFailures = []
            presentationError = String(localized: "The selected files could not be imported. Try again.")
        }
    }

    public func importerCancelled() {
        // A user cancellation is intentionally a no-op: no import report or error is fabricated.
    }

    public func importerFailed() {
        presentationError = String(localized: "The selected files could not be imported. Try again.")
    }

    public func setRepeat(_ mode: RepeatMode) { playback.setRepeatMode(mode) }

    public func toggleShuffle() { playback.toggleShuffle() }

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
            navigation.push(destination)
            isSeeking = false
            filterText = ""
            resetSelection()
        case .play(let track, let queue):
            playback.replaceQueue(with: queue)
            playback.play(track)
            navigation.push(.nowPlaying)
            resetSelection()
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

    private func resetSelection() { selectedIndex = 0 }

    private func row(
        _ id: String,
        _ title: String,
        _ action: ClassicPlayerRow.Action,
        subtitle: String? = nil
    ) -> ClassicPlayerRow {
        ClassicPlayerRow(id: id, title: title, subtitle: subtitle, action: action)
    }

    private func trackRow(_ track: Track, queue: [Track]) -> ClassicPlayerRow {
        ClassicPlayerRow(
            id: "track.\(track.id.uuidString)",
            title: track.title,
            subtitle: "\(track.artist) · \(track.album)",
            action: .play(track, queue: queue)
        )
    }

    private func filtered(_ rows: [ClassicPlayerRow]) -> [ClassicPlayerRow] {
        guard !filterText.isEmpty else { return rows }
        return rows.filter {
            $0.title.localizedCaseInsensitiveContains(filterText)
                || ($0.subtitle?.localizedCaseInsensitiveContains(filterText) ?? false)
        }
    }

    private func filteredTracks(_ tracks: [Track]) -> [Track] {
        guard !filterText.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedCaseInsensitiveContains(filterText)
                || $0.artist.localizedCaseInsensitiveContains(filterText)
                || $0.album.localizedCaseInsensitiveContains(filterText)
        }
    }

    private func albumKeys(in tracks: [Track]) -> [AlbumKey] {
        Array(Set(tracks.map { AlbumKey(artist: $0.artist, title: $0.album) }))
            .sorted { lhs, rhs in
                lhs.artist == rhs.artist ? lhs.title < rhs.title : lhs.artist < rhs.artist
            }
    }

    private func sameReport(_ lhs: TrackImportReport, _ rhs: TrackImportReport?) -> Bool {
        guard let rhs else { return false }
        return lhs.wasCancelled == rhs.wasCancelled
            && lhs.imported.map(\.id) == rhs.imported.map(\.id)
            && lhs.failures.map(\.id) == rhs.failures.map(\.id)
    }

    private func bluetoothKindName(_ kind: BluetoothDeviceKind) -> String {
        switch kind {
        case .automatic: String(localized: "Bluetooth: Automatic")
        case .airPods: String(localized: "Bluetooth: AirPods")
        case .headphones: String(localized: "Bluetooth: Headphones")
        case .speaker: String(localized: "Bluetooth: Speaker")
        }
    }
}
