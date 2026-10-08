import ImageIO
import CoreFoundation
import SwiftUI
import UniformTypeIdentifiers

/// The view callback stays on the UI actor; repositories perform I/O on their own actor.
public typealias ClassicArtworkLoader = @MainActor @Sendable (Track) async -> Data?

/// Functional embedded player UI. Concrete repositories and audio engines remain app-owned dependencies.
public struct ClassicPlayerView: View {
    @State private var model: ClassicPlayerModel
    @AppStorage("vipod.theme") private var themePreference = "black"
    @State private var artworkImage: Image?
    @State private var showsImportFailures = false
    @State private var collectionName = ""
    @State private var showsPlaylistName = false
    @State private var editingPlaylistID: UUID?
    @State private var showsSongOverflow = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let artworkLoader: ClassicArtworkLoader
    private let audioConnection: AudioConnectionMonitor?
    private let deviceNameProvider: @MainActor () -> String

    public init(
        library: LibraryController,
        collections: LibraryCollectionController? = nil,
        playback: PlaybackController,
        artworkLoader: @escaping ClassicArtworkLoader = { _ in nil },
        audioConnection: AudioConnectionMonitor? = nil,
        deviceNameProvider: (@MainActor () -> String)? = nil
    ) {
        let resolveDeviceName = deviceNameProvider ?? { PlayerDeviceNameResolver.currentDisplayName() }
        _model = State(initialValue: ClassicPlayerModel(library: library, playback: playback, collections: collections, audioConnection: audioConnection, deviceName: resolveDeviceName()))
        self.artworkLoader = artworkLoader
        self.audioConnection = audioConnection
        self.deviceNameProvider = resolveDeviceName
    }

    private var theme: iPodTheme { themePreference == "white" ? .classicWhite : .classicBlack }
    private var isBlackTheme: Bool { themePreference != "white" }

    public var body: some View {
        ClassicPlayerSurface(
            theme: theme,
            screen: { display },
            controls: { songActionsToolbar },
            browse: model.browse,
            select: model.selectPressed,
            menu: model.menuPressed,
            playPause: model.togglePlayback,
            next: model.nextPressed,
            previous: model.previousPressed
        )
        .preferredColorScheme(isBlackTheme ? .dark : .light)
        .fileImporter(
            isPresented: $model.isImporterPresented,
            allowedContentTypes: [.mp3, .mpeg4Audio, .wav, .aiff],
            allowsMultipleSelection: true,
            onCompletion: handleImportResult,
            onCancellation: model.importerCancelled
        )
        .task {
            audioConnection?.start()
            await model.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                audioConnection?.refresh()
                model.deviceName = PlayerDeviceNameResolver.displayName(from: deviceNameProvider())
            }
            else if phase == .inactive || phase == .background {
                Task { await model.playback.flushSession() }
            }
        }
        .task(id: model.playback.currentTrack?.id) {
            guard let track = model.playback.currentTrack else {
                artworkImage = nil
                return
            }
            artworkImage = nil
            guard let data = await artworkLoader(track), !Task.isCancelled else { return }
            artworkImage = decodeArtwork(data)
        }
        .onChange(of: model.rows.map(\.id)) { _, _ in model.normalizeSelection() }
        .onChange(of: model.requestedTheme) { _, _ in
            guard let choice = model.consumeRequestedTheme() else { return }
            themePreference = choice.rawValue
        }
        .alert(String(localized: "VIPOD"), isPresented: errorPresented) {
            Button(String(localized: "OK"), role: .cancel) { model.presentationError = nil }
        } message: {
            Text(model.presentationError ?? String(localized: "Something went wrong. Please try again."))
        }
        .confirmationDialog(String(localized: "More Song Actions"), isPresented: $showsSongOverflow, titleVisibility: .visible) {
            songOverflowDialogActions
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.presentationError != nil },
            set: { if !$0 { model.presentationError = nil } }
        )
    }

    private var removalConfirmationPresented: Binding<Bool> {
        Binding(
            get: { model.selectedTrackForRemoval != nil },
            set: { if !$0 { model.cancelTrackRemoval() } }
        )
    }

    private var display: some View {
        VStack(spacing: 0) {
            RetroTitleStatusBar(
                title: model.screenTitle,
                status: model.playbackStatusText,
                theme: theme,
                connectionSymbol: audioConnection?.status?.symbolName,
                connectionLabel: audioConnection?.status?.accessibilityLabel
            )
            displayContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(theme.palette.screenText)
        .background(theme.palette.screen)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("classic.display")
        .alert(
            String(localized: "Remove Song?"),
            isPresented: removalConfirmationPresented,
            presenting: model.selectedTrackForRemoval
        ) { track in
            Button(String(localized: "Remove"), role: .destructive) {
                Task { await model.removeTrack(track) }
            }
            Button(String(localized: "Cancel"), role: .cancel) { model.cancelTrackRemoval() }
        } message: { track in
            Text(String.localizedStringWithFormat(
                String(localized: "Remove %@ from VIPOD? The original audio file will remain on your iPhone."),
                track.title
            ))
        }
    }

    @ViewBuilder
    private var displayContent: some View {
        switch model.navigation.currentDestination {
        case .nowPlaying:
            nowPlayingContent
        case .queue:
            queueContent
        case .settings:
            settingsContent
        case .playlists:
            playlistsContent
        case .playlist(let id):
            playlistContent(id)
        case .playlistSongPicker:
            listContent
        case .favorites:
            favoritesContent
        default:
            listContent
        }
    }

    private var playlistsContent: some View {
        VStack(spacing: 0) {
            if !model.collections.hasLoaded {
                collectionUnavailableView
            } else {
                if let error = model.collections.errorMessage { collectionErrorBanner(error) }
                CollectionRowsView(
                    rows: model.rows,
                    selectedRowID: model.selectedRowID,
                    theme: theme,
                    emptyMessage: String(localized: "No playlists yet."),
                    openIdentifier: { row in "playlist.open.\(row.id.replacingOccurrences(of: "playlist.", with: ""))" },
                    activate: model.activate,
                    selectRow: model.selectRow,
                    reduceMotion: reduceMotion,
                    touchSelectOnly: true,
                    actions: { row in
                        AnyView(EmptyView())
                    },
                    footerAction: nil
                )
            }
        }
        .alert(editingPlaylistID == nil ? String(localized: "New Playlist") : String(localized: "Rename Playlist"), isPresented: $showsPlaylistName) {
            TextField(String(localized: "Playlist Name"), text: $collectionName)
            Button(String(localized: "Save")) {
                let name = collectionName
                if let id = editingPlaylistID { Task { await model.renamePlaylist(id: id, to: name) } }
                else { Task { _ = await model.createPlaylist(named: name) } }
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
        }
    }

    private func playlistContent(_ id: UUID) -> some View {
        let playlist = model.collections.catalog.playlists.first { $0.id == id }
        return Group {
            if !model.collections.hasLoaded {
                collectionUnavailableView
            } else if playlist != nil {
                VStack(spacing: 0) {
                    if let error = model.collections.errorMessage { collectionErrorBanner(error) }
                    CollectionRowsView(
                        rows: model.rows,
                        selectedRowID: model.selectedRowID,
                        theme: theme,
                        emptyMessage: String(localized: "This playlist is empty."),
                        openIdentifier: { "playlist.member.\($0.id.replacingOccurrences(of: "track.", with: ""))" },
                        activate: model.activate,
                        selectRow: model.selectRow,
                        reduceMotion: reduceMotion,
                        touchSelectOnly: true,
                        actions: { row in
                        AnyView(EmptyView())
                        },
                        additions: []
                    )
                }
            } else {
                CollectionMessageView(message: String(localized: "This playlist is no longer available."), theme: theme)
            }
        }
    }

    private var favoritesContent: some View {
        Group {
            if !model.collections.hasLoaded {
                collectionUnavailableView
            } else {
                VStack(spacing: 0) {
                    if let error = model.collections.errorMessage { collectionErrorBanner(error) }
                    CollectionRowsView(
                        rows: model.rows,
                        selectedRowID: model.selectedRowID,
                        theme: theme,
                        emptyMessage: String(localized: "No favorite songs yet."),
                        openIdentifier: { "favorites.track.\($0.id.replacingOccurrences(of: "track.", with: ""))" },
                        activate: model.activate,
                        selectRow: model.selectRow,
                        reduceMotion: reduceMotion,
                        touchSelectOnly: true,
                        actions: { row in
                        AnyView(EmptyView())
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var collectionUnavailableView: some View {
        if let error = model.collections.errorMessage {
            VStack(spacing: 8) {
                Text(error).accessibilityIdentifier("collections.error")
                Button(String(localized: "Retry")) { Task { await model.collections.load() } }
                    .accessibilityIdentifier("collections.retry")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView(String(localized: "Loading Collections…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func collectionErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("collections.error")
            Button(String(localized: "Retry")) { Task { await model.collections.load() } }
                .accessibilityIdentifier("collections.retry")
        }
        .padding(.horizontal, 10)
    }

    private var listContent: some View {
        LibraryBrowserView(
            presentation: LibraryBrowserPresentation(
                rows: model.rows,
                selectedRowID: model.selectedRowID,
                selectedRowTitle: model.selectedRow?.title,
                theme: theme,
                reduceMotion: reduceMotion,
                isImporting: model.library.isImporting,
                isLoading: model.library.isLoading,
                loadFailed: model.loadFailed,
                hasTracks: !model.library.tracks.isEmpty,
                shouldShowEmptyLibrary: model.shouldShowEmptyLibrary,
                usesSplitMenu: usesSplitMenu,
                isMainMenu: model.navigation.currentDestination == .mainMenu,
                isFilterable: isFilterable,
                isSongs: model.navigation.currentDestination == .songs,
                filterText: $model.filterText,
                canRemoveSelectedTrack: model.canRemoveSelectedTrack,
                summary: model.importSummary,
                failures: model.importFailures,
                failuresExpanded: $showsImportFailures,
                hasLibraryError: model.library.errorMessage != nil,
                preview: MenuArtworkPreview(
                    track: model.playback.currentTrack,
                    artwork: artworkImage,
                    durationText: model.currentTrackDurationText,
                    hint: previewHint,
                    theme: theme
                )
            ),
            actions: LibraryBrowserActions(
                importMusic: { model.isImporterPresented = true },
                removeSelectedSong: model.requestSelectedTrackRemoval,
                retryLoad: { Task { await model.retryLoad() } },
                activate: model.activate,
                selectRow: model.selectRow,
                playNext: model.playNext,
                addLast: model.addLast,
                favorite: { track in Task { await model.toggleFavorite(track.id) } },
                playlists: model.collections.catalog.playlists,
                addToPlaylist: { track, playlistID in Task { await model.addToPlaylist(track.id, playlistID: playlistID) } }
            ),
            titleForRow: { $0.title },
            subtitleForRow: { $0.subtitle }
        )
    }

    private var settingsContent: some View {
        PlayerSettingsView(
            rows: model.rows,
            selectedRowID: model.selectedRowID,
            theme: theme,
            reduceMotion: reduceMotion,
            isImporting: model.library.isImporting,
            isLoading: model.library.isLoading,
            loadFailed: model.loadFailed,
            hasTracks: !model.library.tracks.isEmpty,
            summary: model.importSummary,
            failures: model.importFailures,
            failuresExpanded: $showsImportFailures,
            hasLibraryError: model.library.errorMessage != nil,
            outputName: audioConnection?.output?.name,
            outputKind: audioConnection?.deviceKind,
            presentation: settingsPresentation,
            retryAction: { Task { await model.retryLoad() } },
            activate: model.activate
        )
    }

    private var settingsPresentation: PlayerSettingsPresentation {
        PlayerSettingsPresentation(
            isBlackTheme: isBlackTheme,
            isShuffled: model.playback.isShuffled,
            repeatMode: model.playback.repeatMode,
            preferredBluetoothKind: audioConnection?.preferredDeviceKind,
            deviceName: model.deviceName
        )
    }

    private var usesSplitMenu: Bool {
        switch model.navigation.currentDestination {
        case .mainMenu, .music: true
        default: false
        }
    }

    private var previewHint: String {
        if model.loadFailed { return String(localized: "Library preview is unavailable.") }
        if model.library.tracks.isEmpty { return String(localized: "Import music to add artwork") }
        return String(localized: "Choose a song to preview artwork")
    }

    private var nowPlayingContent: some View {
        NowPlayingView(
            track: model.playback.currentTrack,
            previousTrack: model.playback.queue.previousTrack,
            nextTrack: model.playback.queue.nextTrack,
            artwork: artworkImage,
            elapsed: model.playback.elapsed, duration: model.playback.duration,
            elapsedText: model.formattedTime(model.playback.elapsed),
            durationText: model.formattedTime(model.playback.duration),
            isSeeking: model.isSeeking, hasPlaybackError: model.playback.errorMessage != nil,
            theme: theme, onSeek: model.playback.seek(to:), onRetry: { model.playback.play() }
        )
    }

    private var queueContent: some View {
        PlaybackQueueView(
            tracks: model.playback.queue.orderedTracks,
            currentTrackID: model.playback.currentTrack?.id,
            selectedTrackID: model.selectedQueueTrackID,
            theme: theme,
            select: model.selectQueueTrack,
            reduceMotion: reduceMotion
        )
    }

    private func decodeArtwork(_ data: Data) -> Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: image, scale: 1)
    }

    private var isFilterable: Bool {
        switch model.navigation.currentDestination {
        case .artists, .artistAlbums, .artistSongs, .artistAlbum, .albums, .album, .songs: true
        default: false
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            showsImportFailures = false
            Task { await model.importFiles(from: urls) }
        case .failure(let error) where error is CancellationError:
            model.importerCancelled()
        case .failure:
            model.importerFailed()
        }
    }

    @ViewBuilder
    private var songActionsToolbar: some View {
        if model.navigation.currentDestination == .queue {
            queueActionsToolbar
        } else if model.navigation.currentDestination == .playlists {
            playlistActionsToolbar
        } else if case .playlist(let id) = model.navigation.currentDestination {
            playlistMemberActionsToolbar(id: id)
        } else if case .playlistSongPicker = model.navigation.currentDestination {
            playlistSongPickerActionsToolbar
        } else if model.navigation.currentDestination == .favorites {
            favoriteActionsToolbar
        } else if model.shouldShowSongActions {
            SongActionsToolbar(
                selectedTrack: model.selectedSongTrack,
                canRemove: model.canRemoveSelectedTrack,
                isFavorite: model.isSelectedTrackFavorite,
                playlists: model.collections.catalog.playlists,
                theme: theme,
                onPlayNext: {
                    if let track = model.selectedSongTrack {
                        model.playNext(track)
                    }
                },
                onAddQueue: {
                    if let track = model.selectedSongTrack {
                        model.addLast(track)
                    }
                },
                onToggleFavorite: {
                    if let track = model.selectedSongTrack {
                        Task { await model.toggleFavorite(track.id) }
                    }
                },
                onAddToPlaylist: { playlistID in
                    if let track = model.selectedSongTrack {
                        Task { await model.addToPlaylist(track.id, playlistID: playlistID) }
                    }
                },
                onRemove: {
                    model.requestSelectedTrackRemoval()
                }
            )
            .transition(.opacity)
        }
    }

    private var queueActionsToolbar: some View {
        let tracks = model.playback.queue.orderedTracks
        let index = model.selectedQueueTrackID.flatMap { id in tracks.firstIndex(where: { $0.id == id }) }
        return ContextualActionToolbar(actions: [
            contextualAction("queue.moveUp", "Move Up", "arrow.up", enabled: index != nil && index != 0) {
                model.moveSelectedQueueTrack(by: -1)
            },
            contextualAction("queue.moveDown", "Move Down", "arrow.down", enabled: index != nil && index != tracks.count - 1) {
                model.moveSelectedQueueTrack(by: 1)
            },
            contextualAction("queue.remove", "Remove from Queue", "minus.circle", enabled: index != nil) {
                model.removeSelectedQueueTrack()
            }
        ], theme: theme)
    }

    private var playlistActionsToolbar: some View {
        let selected = model.selectedRow
        let selectedID: UUID? = { if case .open(.playlist(let id))? = selected?.action { return id }; return nil }()
        return ContextualActionToolbar(actions: [
            contextualAction("playlist.create", "Create Playlist", "plus") {
                editingPlaylistID = nil
                collectionName = ""
                showsPlaylistName = true
            },
            contextualAction("playlist.rename", "Rename Playlist", "pencil", enabled: selectedID != nil) {
                guard let selectedID else { return }
                editingPlaylistID = selectedID
                collectionName = selected?.title ?? ""
                showsPlaylistName = true
            },
            contextualAction("playlist.delete", "Delete Playlist", "trash", enabled: selectedID != nil) {
                if let selectedID { Task { await model.deletePlaylist(id: selectedID) } }
            }
        ], theme: theme)
    }

    private func playlistMemberActionsToolbar(id: UUID) -> some View {
        let playlist = model.collections.catalog.playlists.first { $0.id == id }
        let track = model.selectedSongTrack
        let index = track.flatMap { selected in playlist?.trackIDs.firstIndex(of: selected.id) }
        return ContextualActionToolbar(actions: [
            contextualAction("playlist.addSongs", "Add Songs", "plus", enabled: model.library.tracks.contains(where: { candidate in !(playlist?.trackIDs.contains(candidate.id) ?? true) })) {
                model.openPlaylistSongPicker(for: id)
            },
            contextualAction("playlist.moveUp", "Move Up", "arrow.up", enabled: index != nil && index != 0) {
                if let track { Task { await model.movePlaylistTrack(playlistID: id, trackID: track.id, by: -1) } }
            },
            contextualAction("playlist.moveDown", "Move Down", "arrow.down", enabled: index != nil && index != (playlist?.trackIDs.count ?? 0) - 1) {
                if let track { Task { await model.movePlaylistTrack(playlistID: id, trackID: track.id, by: 1) } }
            },
            contextualAction("playlist.remove", "Remove from Playlist", "minus.circle", enabled: track != nil) {
                if let track { Task { await model.removeFromPlaylist(track.id, playlistID: id) } }
            },
            contextualAction("playlist.more", "More Song Actions", "ellipsis", enabled: track != nil) {
                showsSongOverflow = true
            }
        ], theme: theme)
    }

    private var playlistSongPickerActionsToolbar: some View {
        let selectedTrack: Track? = {
            guard let selected = model.selectedRow,
                  case .addToPlaylist(let track, _) = selected.action else { return nil }
            return track
        }()
        return ContextualActionToolbar(actions: [
            contextualAction("playlist.addSelectedSong", "Add Selected Song", "plus", enabled: selectedTrack != nil) {
                model.selectCurrent()
            }
        ], theme: theme)
    }

    private var favoriteActionsToolbar: some View {
        let track = model.selectedSongTrack
        return ContextualActionToolbar(actions: [
            contextualAction("favorite.toggle", model.isSelectedTrackFavorite ? "Remove Favorite" : "Add Favorite", model.isSelectedTrackFavorite ? "heart.slash" : "heart", enabled: track != nil) {
                if let track { Task { await model.toggleFavorite(track.id) } }
            },
            contextualAction("favorite.more", "More Song Actions", "ellipsis", enabled: track != nil) {
                showsSongOverflow = true
            }
        ], theme: theme)
    }

    private func contextualAction(
        _ id: String,
        _ title: String,
        _ icon: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> ContextualPlayerAction {
        ContextualPlayerAction(
            id: id,
            title: String(localized: String.LocalizationValue(title)),
            icon: icon,
            isEnabled: enabled,
            action: action
        )
    }

    @ViewBuilder
    private var songOverflowDialogActions: some View {
        if let track = model.selectedSongTrack {
            Button(String(localized: "Play Next")) { model.playNext(track) }
            Button(String(localized: "Add to Queue")) { model.addLast(track) }
            Button(model.isSelectedTrackFavorite ? String(localized: "Remove Favorite") : String(localized: "Add Favorite")) {
                Task { await model.toggleFavorite(track.id) }
            }
            ForEach(model.collections.catalog.playlists) { playlist in
                Button(String.localizedStringWithFormat(String(localized: "Add to %@"), playlist.name)) {
                    Task { await model.addToPlaylist(track.id, playlistID: playlist.id) }
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
        }
    }
}
