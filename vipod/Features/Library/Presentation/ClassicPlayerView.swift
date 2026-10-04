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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let artworkLoader: ClassicArtworkLoader
    private let audioConnection: AudioConnectionMonitor?

    public init(
        library: LibraryController,
        collections: LibraryCollectionController? = nil,
        playback: PlaybackController,
        artworkLoader: @escaping ClassicArtworkLoader = { _ in nil },
        audioConnection: AudioConnectionMonitor? = nil
    ) {
        _model = State(initialValue: ClassicPlayerModel(library: library, playback: playback, collections: collections, audioConnection: audioConnection))
        self.artworkLoader = artworkLoader
        self.audioConnection = audioConnection
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
            if phase == .active { audioConnection?.refresh() }
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
        .onChange(of: model.rows.count) { _, _ in model.normalizeSelection() }
        .onChange(of: model.requestedTheme) { _, _ in
            guard let choice = model.consumeRequestedTheme() else { return }
            themePreference = choice.rawValue
        }
        .alert(String(localized: "VIPOD"), isPresented: errorPresented) {
            Button(String(localized: "OK"), role: .cancel) { model.presentationError = nil }
        } message: {
            Text(model.presentationError ?? String(localized: "Something went wrong. Please try again."))
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
                    actions: { row in
                        guard case .open(.playlist(let id)) = row.action else { return AnyView(EmptyView()) }
                        return AnyView(Menu {
                            Button(String(localized: "Rename Playlist"), systemImage: "pencil") {
                                editingPlaylistID = id
                                collectionName = row.title
                                showsPlaylistName = true
                            }.accessibilityIdentifier("playlist.rename.\(id.uuidString)")
                            Button(String(localized: "Delete Playlist"), systemImage: "trash", role: .destructive) {
                                Task { await model.deletePlaylist(id: id) }
                            }.accessibilityIdentifier("playlist.delete.\(id.uuidString)")
                        } label: {
                            Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(String.localizedStringWithFormat(String(localized: "Actions for %@"), row.title))
                        .accessibilityIdentifier("playlist.actions.\(id.uuidString)"))
                    },
                    footerAction: CollectionAddition(title: String(localized: "Create Playlist"), identifier: "playlist.create") {
                        editingPlaylistID = nil
                        collectionName = ""
                        showsPlaylistName = true
                    }
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
            } else if let playlist {
                VStack(spacing: 0) {
                    if let error = model.collections.errorMessage { collectionErrorBanner(error) }
                    CollectionRowsView(
                        rows: model.rows,
                        selectedRowID: model.selectedRowID,
                        theme: theme,
                        emptyMessage: String(localized: "This playlist is empty."),
                        openIdentifier: { "playlist.member.\($0.id.replacingOccurrences(of: "track.", with: ""))" },
                        activate: model.activate,
                        actions: { row in
                        guard case .play(let track, _) = row.action,
                              let index = playlist.trackIDs.firstIndex(of: track.id) else { return AnyView(EmptyView()) }
                        return AnyView(Menu {
                            Button(String(localized: "Move Up"), systemImage: "arrow.up") {
                                Task { await model.movePlaylistTrack(playlistID: id, trackID: track.id, by: -1) }
                            }
                            .disabled(index == 0)
                            .accessibilityIdentifier("playlist.moveUp.\(track.id.uuidString)")
                            Button(String(localized: "Move Down"), systemImage: "arrow.down") {
                                Task { await model.movePlaylistTrack(playlistID: id, trackID: track.id, by: 1) }
                            }
                            .disabled(index == playlist.trackIDs.count - 1)
                            .accessibilityIdentifier("playlist.moveDown.\(track.id.uuidString)")
                            Button(String(localized: "Remove from Playlist"), systemImage: "minus.circle", role: .destructive) {
                                Task { await model.removeFromPlaylist(track.id, playlistID: id) }
                            }
                            .accessibilityIdentifier("playlist.remove.\(track.id.uuidString)")
                        } label: {
                            Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(String.localizedStringWithFormat(String(localized: "Actions for %@"), track.title))
                        .accessibilityIdentifier("playlist.member.actions.\(track.id.uuidString)"))
                        },
                        additions: model.library.tracks.filter { !playlist.trackIDs.contains($0.id) }.map { track in
                            CollectionAddition(title: String.localizedStringWithFormat(String(localized: "Add %@"), track.title), identifier: "playlist.add.\(track.id.uuidString)") {
                                Task { await model.addToPlaylist(track.id, playlistID: id) }
                            }
                        }
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
                        actions: { row in
                        guard case .play(let track, _) = row.action else { return AnyView(EmptyView()) }
                        return AnyView(Button(String(localized: "Remove Favorite"), systemImage: "heart.slash") {
                            Task { await model.toggleFavorite(track.id) }
                        }
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel(String(localized: "Remove Favorite"))
                        .accessibilityValue(String(localized: "Favorite"))
                        .accessibilityIdentifier("favorite.toggle.\(track.id.uuidString)"))
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
            preferredBluetoothKind: audioConnection?.preferredDeviceKind
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
            playTrack: { id in model.selectQueueTrack(id); model.playSelectedQueueTrack() },
            moveUp: { model.moveSelectedQueueTrack(by: -1) },
            moveDown: { model.moveSelectedQueueTrack(by: 1) },
            remove: model.removeSelectedQueueTrack
        )
    }

    private func decodeArtwork(_ data: Data) -> Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: image, scale: 1)
    }

    private var isFilterable: Bool {
        switch model.navigation.currentDestination {
        case .artists, .artist, .albums, .album, .songs: true
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
        if model.shouldShowSongActions {
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
}
