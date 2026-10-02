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
        case .settings:
            listContent
        default:
            listContent
        }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            if model.library.isImporting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "Importing Music…"))
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 30)
                .accessibilityElement(children: .combine)
            }
            if model.navigation.currentDestination == .settings, let output = audioConnection?.output {
                VStack(spacing: 2) {
                    Text(String.localizedStringWithFormat(String(localized: "Connected device: %@"), output.name))
                    if audioConnection?.deviceKind == .airPods {
                        Text(String(localized: "Battery level is unavailable."))
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.palette.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 34)
                .accessibilityIdentifier("settings.bluetooth.route")
            }
            if isFilterable {
                HStack(spacing: 6) {
                    Text(String(localized: "Find"))
                        .font(.system(size: 12, weight: .semibold))
                    TextField(String(localized: "Filter music"), text: $model.filterText)
                        .font(.system(size: 13))
                        .textFieldStyle(.plain)
                        .accessibilityLabel(String(localized: "Filter music"))
                    if model.navigation.currentDestination == .songs {
                        Button(action: model.requestSelectedTrackRemoval) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(model.canRemoveSelectedTrack ? Color.red : theme.palette.secondaryText)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.canRemoveSelectedTrack)
                        .accessibilityIdentifier("library.remove")
                        .accessibilityLabel(model.selectedRow.map {
                            String.localizedStringWithFormat(String(localized: "Remove %@"), $0.title)
                        } ?? String(localized: "Remove selected song"))
                        .accessibilityValue(model.selectedRow?.title ?? String(localized: "No song selected"))
                    }
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 38)
                .overlay(alignment: .bottom) { theme.palette.separator.opacity(0.65).frame(height: 1) }
            }

            if model.loadFailed && model.library.tracks.isEmpty && model.navigation.currentDestination != .mainMenu {
                loadFailurePanel
            } else if model.library.isLoading && model.library.tracks.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(String(localized: "Loading Music…"))
                        .font(.system(size: 14))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.shouldShowEmptyLibrary && !usesSplitMenu {
                emptyLibrary
            } else if usesSplitMenu {
                splitMenuDisplay
            } else {
                rowsList
            }

            if let summary = model.importSummary {
                importReport(summary)
            }
            if model.loadFailed && model.library.tracks.isEmpty && model.navigation.currentDestination == .mainMenu {
                loadFailurePanel
            }
            if model.library.errorMessage != nil {
                Text(String(localized: "The music library needs attention."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.palette.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
    }

    private var usesSplitMenu: Bool {
        switch model.navigation.currentDestination {
        case .mainMenu, .music: true
        default: false
        }
    }

    private var rowsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        menuRow(row)
                            .id(row.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.selectedRowID) { _, rowID in
                guard let rowID else { return }
                if reduceMotion { proxy.scrollTo(rowID, anchor: .center) }
                else { withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo(rowID, anchor: .center) } }
            }
            .onAppear {
                if let rowID = model.selectedRowID { proxy.scrollTo(rowID, anchor: .center) }
            }
        }
    }

    private var splitMenuDisplay: some View {
        GeometryReader { proxy in
            if proxy.size.width < 280 {
                rowsList
            } else {
                HStack(alignment: .top, spacing: 0) {
                    rowsList
                        .frame(width: proxy.size.width * 0.66)
                    theme.palette.separator.opacity(0.7)
                        .frame(width: 1)
                    artworkPreview
                        .frame(width: proxy.size.width * 0.34 - 1, height: proxy.size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var artworkPreview: some View {
        GeometryReader { proxy in
            // Reserve space for a two-line title, artist, and duration even on short panels.
            let metadataHeight: CGFloat = 82
            let imageSide = min(max(0, proxy.size.width - 12), max(0, proxy.size.height - metadataHeight - 12))
            VStack(spacing: 5) {
                RetroArtworkFrame(artwork: artworkImage, theme: theme)
                    .frame(width: imageSide, height: imageSide)
                if let track = model.playback.currentTrack {
                    Text(track.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(track.artist)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                    Text(String.localizedStringWithFormat(String(localized: "Duration: %@"), model.currentTrackDurationText))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel(String.localizedStringWithFormat(String(localized: "Duration %@"), model.currentTrackDurationText))
                        .accessibilityIdentifier("menu.trackDuration")
                } else {
                    Text(previewHint)
                        .font(.system(size: 10, weight: .medium))
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(theme.palette.screenText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 7)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("menu.artworkPreview")
        }
    }

    private var previewHint: String {
        if model.loadFailed { return String(localized: "Library preview is unavailable.") }
        if model.library.tracks.isEmpty { return String(localized: "Import music to add artwork") }
        return String(localized: "Choose a song to preview artwork")
    }

    private var emptyLibrary: some View {
        VStack(spacing: 8) {
            Text(String(localized: "Your music library is empty."))
                .font(.system(size: 14, weight: .medium))
            Button {
                model.isImporterPresented = true
            } label: {
                Text(String(localized: "Import Music"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.palette.selectionText)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(theme.palette.selection)
            }
            .buttonStyle(.plain)
            .disabled(model.library.isImporting)
            .accessibilityIdentifier("library.import")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
    }

    private func menuRow(_ row: ClassicPlayerRow) -> some View {
        let isSelected = row.id == model.selectedRowID
        let title: String = {
            switch row.id {
            case "theme.black": return String(localized: "Black iPod")
            case "theme.white": return String(localized: "White iPod")
            case "settings.shuffle": return String(localized: "Shuffle")
            case "repeat.off": return String(localized: "Repeat Off")
            case "repeat.all": return String(localized: "Repeat All")
            case "repeat.one": return String(localized: "Repeat One")
            default: return row.title
            }
        }()
        let subtitle = settingsSubtitle(for: row)

        return RetroMenuRow(
            title: title,
            subtitle: subtitle ?? row.subtitle,
            isSelected: isSelected,
            theme: theme,
            action: { activate(row) }
        )
        .disabled(row.id == "menu.import" && model.library.isImporting)
        .accessibilityIdentifier(accessibilityID(for: row))
    }

    private func activate(_ row: ClassicPlayerRow) {
        model.activate(row)
    }

    private func accessibilityID(for row: ClassicPlayerRow) -> String {
        switch row.id {
        case "menu.music", "menu.settings", "menu.import", "menu.nowPlaying", "theme.black", "theme.white": row.id
        default: row.id
        }
    }

    private func settingsSubtitle(for row: ClassicPlayerRow) -> String? {
        switch row.id {
        case "theme.black": isBlackTheme ? String(localized: "Selected") : nil
        case "theme.white": isBlackTheme ? nil : String(localized: "Selected")
        case "settings.shuffle": model.playback.isShuffled ? String(localized: "On") : String(localized: "Off")
        case "repeat.off": model.playback.repeatMode == .off ? String(localized: "Selected") : nil
        case "repeat.all": model.playback.repeatMode == .all ? String(localized: "Selected") : nil
        case "repeat.one": model.playback.repeatMode == .one ? String(localized: "Selected") : nil
        case "settings.bluetooth.automatic": audioConnection?.preferredDeviceKind == .automatic ? String(localized: "Selected") : nil
        case "settings.bluetooth.airPods": audioConnection?.preferredDeviceKind == .airPods ? String(localized: "Selected") : nil
        case "settings.bluetooth.headphones": audioConnection?.preferredDeviceKind == .headphones ? String(localized: "Selected") : nil
        case "settings.bluetooth.speaker": audioConnection?.preferredDeviceKind == .speaker ? String(localized: "Selected") : nil
        default: nil
        }
    }

    private var nowPlayingContent: some View {
        ScrollView {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    RetroArtworkFrame(artwork: artworkImage, theme: theme)
                        .frame(width: 78, height: 78)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.playback.currentTrack?.title ?? String(localized: "Nothing Playing"))
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(2)
                            .accessibilityIdentifier("nowPlaying.title")
                        Text(model.playback.currentTrack?.artist ?? String(localized: "Choose a song from Music"))
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Text(model.playback.currentTrack?.album ?? "")
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)

                VStack(spacing: 1) {
                    Slider(
                        value: Binding(
                            get: { min(max(model.playback.elapsed, 0), max(model.playback.duration, 1)) },
                            set: { model.playback.seek(to: $0) }
                        ),
                        in: 0...max(model.playback.duration, 1)
                    )
                    .tint(theme.palette.selection)
                    .disabled(model.playback.duration <= 0)
                    .accessibilityLabel(String(localized: "Playback position"))
                    .accessibilityHint(model.playback.duration > 0
                        ? String(localized: "Adjust playback position")
                        : String(localized: "Seeking is unavailable until the track duration is known."))
                    RetroPlaybackProgress(
                        progress: model.playback.duration > 0 ? model.playback.elapsed / model.playback.duration : 0,
                        elapsed: model.formattedTime(model.playback.elapsed),
                        duration: model.formattedTime(model.playback.duration),
                        theme: theme
                    )
                }
                .padding(.horizontal, 10)

                Text(model.isSeeking
                    ? String(localized: "Rotate to seek · Select to finish")
                    : String(localized: "Select to enable wheel seeking"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.palette.secondaryText)
                    .frame(minHeight: 18)
                    .accessibilityIdentifier("nowPlaying.seekHint")
                if model.playback.errorMessage != nil {
                    Button(String(localized: "Playback needs attention · Try Again")) {
                        model.playback.play()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHint(String(localized: "Retry playing the current track"))
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 5)
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

    private func importReport(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary).font(.system(size: 10, weight: .semibold))
            if !model.importFailures.isEmpty {
                Button {
                    showsImportFailures.toggle()
                } label: {
                    Text(showsImportFailures
                        ? String(localized: "Hide failed files")
                        : String.localizedStringWithFormat(String(localized: "Show %lld failed files"), model.importFailures.count))
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library.importFailures")
                if showsImportFailures {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(model.importFailures, id: \.self) { filename in
                                Text(String.localizedStringWithFormat(String(localized: "Could not import %@"), filename))
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxHeight: 68)
                    .scrollIndicators(.hidden)
                }
            }
        }
        .foregroundStyle(theme.palette.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var loadFailurePanel: some View {
        VStack(spacing: 6) {
            Text(String(localized: "The music library could not be loaded."))
                .font(.system(size: 12, weight: .medium))
            Button {
                Task { await model.retryLoad() }
            } label: {
                HStack(spacing: 6) {
                    if model.library.isLoading { ProgressView().controlSize(.small) }
                    Text(String(localized: "Retry Library Load"))
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(minHeight: 44)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .disabled(model.library.isLoading)
            .accessibilityIdentifier("library.retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
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
