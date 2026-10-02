import Foundation
import Observation

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

    public init(library: LibraryController, playback: PlaybackController, audioConnection: AudioConnectionMonitor? = nil) {
        self.library = library
        self.playback = playback
        self.audioConnection = audioConnection
        self.operations = ClassicPlayerLibraryOperations(library: library, playback: playback)
    }

    // View teardown requires no actor-isolated work; avoid the same simulator
    // runtime deinit path as the library and playback controllers.
    nonisolated deinit {}

    public var rows: [ClassicPlayerRow] {
        menuBuilder.rows(
            for: navigation.currentDestination,
            tracks: library.tracks,
            filterText: filterText,
            hasConnectedAudioOutput: audioConnection?.output != nil
        )
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
        let currentRows = rows
        guard !currentRows.isEmpty else {
            if navigation.currentDestination == .nowPlaying, isSeeking {
                let adjustment = max(playback.duration * 0.01, 5) * Double(delta)
                playback.seek(to: playback.elapsed + adjustment)
            }
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), currentRows.count - 1)
    }

    public func normalizeSelection() {
        let currentRows = rows
        selectedIndex = currentRows.isEmpty ? 0 : min(max(selectedIndex, 0), currentRows.count - 1)
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

    private var removableSelectedTrack: Track? {
        guard navigation.currentDestination == .songs,
              !library.isLoading, !library.isImporting, !library.isRemoving,
              let selectedRow,
              case .play(let track, _) = selectedRow.action,
              library.tracks.contains(where: { $0.id == track.id }) else { return nil }
        return track
    }
}
