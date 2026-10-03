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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let artworkLoader: ClassicArtworkLoader
    private let audioConnection: AudioConnectionMonitor?

    public init(
        library: LibraryController,
        playback: PlaybackController,
        artworkLoader: @escaping ClassicArtworkLoader = { _ in nil },
        audioConnection: AudioConnectionMonitor? = nil
    ) {
        _model = State(initialValue: ClassicPlayerModel(library: library, playback: playback, audioConnection: audioConnection))
        self.artworkLoader = artworkLoader
        self.audioConnection = audioConnection
    }

    private var theme: iPodTheme { themePreference == "white" ? .classicWhite : .classicBlack }
    private var isBlackTheme: Bool { themePreference != "white" }

    public var body: some View {
        ClassicPlayerSurface(
            theme: theme,
            screen: { display },
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
        default:
            listContent
        }
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
                playNext: model.playNext,
                addLast: model.addLast
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
            track: model.playback.currentTrack, artwork: artworkImage,
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
}
