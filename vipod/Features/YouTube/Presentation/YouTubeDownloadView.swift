import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
struct YouTubeDownloadView: View {
    @Bindable private var controller: YouTubeDownloadController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("vipod.theme") private var themePreference = "black"

    init(controller: YouTubeDownloadController) { self.controller = controller }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    linkEntry
                    if let preview = controller.retainedPreview {
                        previewCard(preview)
                        musicBrainzSearch
                        metadataEditor
                    }
                    if isWorking { workStatus }
                    if case .failed(let message) = controller.state { failure(message) }
                    if case .cancelled = controller.state {
                        Text("Download stopped. Any track already saved remains in your library.")
                            .accessibilityIdentifier("youtube.download.cancelled")
                    }
                    if let track = controller.savedTrackReceipt {
                        savedReceipt(track, cancelled: controller.receiptCancellationArrivedAfterCommit)
                    }
                }
                .padding()
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("YouTube Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("youtube.download.done")
                }
            }
        }
        .preferredColorScheme(themePreference == "white" ? .light : .dark)
    }

    private var linkEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste a public video link to review its details before saving.")
                .font(.subheadline).foregroundStyle(.secondary)
            TextField("YouTube video URL", text: $controller.urlText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .disabled(controller.isBusy)
                .accessibilityIdentifier("youtube.download.url")
                .accessibilityValue(controller.urlText.isEmpty ? "No URL entered" : controller.urlText)
            if isWorking {
                Button("Cancel", action: controller.cancel)
                    .disabled(isCancelling)
                    .accessibilityIdentifier("youtube.download.cancel")
            } else if controller.previewExists {
                Button(action: controller.downloadPreview) {
                    Label(controller.isPreviewReady ? "Download M4A" : "Retry download", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isBusy || !controller.isMetadataValid)
                .accessibilityIdentifier("youtube.download.confirm")
            } else {
                Button(action: controller.submit) {
                    Label("Get information", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isBusy || controller.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("youtube.download.analyze")
            }
        }
    }

    private func previewCard(_ preview: YouTubeVideoPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                previewArtwork(preview)
                VStack(alignment: .leading, spacing: 5) {
                    Text(controller.metadataDraft?.title ?? preview.effectiveMetadata.title)
                        .font(.headline).accessibilityIdentifier("youtube.preview.title")
                    if let artist = nonempty(controller.metadataDraft?.artist) { Text(artist).font(.subheadline) }
                    if let album = nonempty(controller.metadataDraft?.album) { Text(album).font(.subheadline).foregroundStyle(.secondary) }
                    if let albumArtist = nonempty(controller.metadataDraft?.albumArtist) {
                        Text("Album artist: \(albumArtist)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("YouTube title: \(preview.videoTitle)").font(.caption).foregroundStyle(.secondary)
                    if let channel = preview.channel { Text("Source: \(channel)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            artworkSourcePicker
            metadataRows(preview)
            if let format = preview.formats.first {
                HStack {
                    Text("AAC / M4A")
                    Spacer()
                    if let bitrate = format.bitrate { Text("\(Int(bitrate.rounded())) kb/s") }
                    if let size = format.filesize { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
                    else if let size = format.filesizeApprox { Text("About \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("youtube.download.preview")
    }

    @ViewBuilder
    private func previewArtwork(_ preview: YouTubeVideoPreview) -> some View {
        if controller.selectedArtworkSource == .musicBrainz,
           let data = controller.musicBrainzArtwork,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: 116, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("MusicBrainz album cover")
        } else if let thumbnailURL = preview.thumbnailURL {
            AsyncImage(url: thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary).overlay { ProgressView() }
            }
            .frame(width: 116, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("YouTube video thumbnail")
        } else {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                .frame(width: 116, height: 72)
                .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
                .accessibilityLabel("No artwork available")
        }
    }

    private var artworkSourcePicker: some View {
        HStack(spacing: 8) {
            artworkSourceButton(.youtube, title: "YouTube thumbnail")
            artworkSourceButton(.musicBrainz, title: "MusicBrainz cover")
        }
    }

    private func artworkSourceButton(
        _ source: YouTubeDownloadController.ArtworkSource,
        title: String
    ) -> some View {
        let isSelected = controller.selectedArtworkSource == source
        return Button {
            controller.selectArtworkSource(source)
        } label: {
            Label(title, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? .accentColor : .secondary)
        .disabled(controller.isBusy || (source == .musicBrainz && !controller.hasMusicBrainzArtwork))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier(source == .youtube ? "youtube.artwork.source.youtube" : "youtube.artwork.source.musicbrainz")
    }

    @ViewBuilder
    private func metadataRows(_ preview: YouTubeVideoPreview) -> some View {
        let draft = controller.metadataDraft
        if let duration = preview.duration { metadataRow("Duration", value: Self.durationText(duration)) }
        if let date = nonempty(draft?.releaseDate) { metadataRow("Release date", value: date) }
        if let genre = nonempty(draft?.genre) { metadataRow("Genre", value: genre) }
        if let number = nonempty(draft?.trackNumber) {
            let total = nonempty(draft?.trackNumberTotal)
            metadataRow("Track", value: total.map { "\(number)/\($0)" } ?? number)
        }
        if let number = nonempty(draft?.discNumber) {
            let total = nonempty(draft?.discNumberTotal)
            metadataRow("Disc", value: total.map { "\(number)/\($0)" } ?? number)
        }
        if let uploadDate = preview.uploadDate { metadataRow("Video upload date", value: uploadDate) }
    }

    private var metadataEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Music metadata").font(.headline)
            Text("Edit these values before downloading. The original YouTube title remains unchanged.")
                .font(.caption).foregroundStyle(.secondary)
            metadataField("Title", keyPath: \.title, identifier: "youtube.metadata.title")
            metadataField("Artist", keyPath: \.artist, identifier: "youtube.metadata.artist")
            metadataField("Album", keyPath: \.album, identifier: "youtube.metadata.album")
            metadataField("Album artist", keyPath: \.albumArtist, identifier: "youtube.metadata.albumArtist")
            metadataField("Release date", keyPath: \.releaseDate, identifier: "youtube.metadata.releaseDate")
            metadataField("Genre", keyPath: \.genre, identifier: "youtube.metadata.genre")
            HStack(spacing: 8) {
                metadataField("Track number", keyPath: \.trackNumber, identifier: "youtube.metadata.trackNumber", numeric: true)
                metadataField("Track total", keyPath: \.trackNumberTotal, identifier: "youtube.metadata.trackNumberTotal", numeric: true)
            }
            HStack(spacing: 8) {
                metadataField("Disc number", keyPath: \.discNumber, identifier: "youtube.metadata.discNumber", numeric: true)
                metadataField("Disc total", keyPath: \.discNumberTotal, identifier: "youtube.metadata.discNumberTotal", numeric: true)
            }
            if let message = controller.metadataValidationMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
                    .accessibilityIdentifier("youtube.metadata.validation")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("youtube.metadata.editor")
    }

    private func metadataField(
        _ title: String,
        keyPath: WritableKeyPath<YouTubeMetadataDraft, String>,
        identifier: String,
        numeric: Bool = false
    ) -> some View {
        TextField(title, text: Binding(
            get: { controller.metadataDraft?[keyPath: keyPath] ?? "" },
            set: { controller.updateMetadataDraft(keyPath, value: $0) }
        ))
        .textFieldStyle(.roundedBorder)
        .keyboardType(numeric ? .numberPad : .default)
        .textInputAutocapitalization(numeric ? .never : .words)
        .autocorrectionDisabled()
        .disabled(controller.isBusy)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private var musicBrainzSearch: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find a recording with MusicBrainz").font(.subheadline.weight(.semibold))
            TextField("Search title", text: $controller.musicBrainzQuery)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .disabled(controller.isBusy)
                .accessibilityLabel("MusicBrainz search title")
                .accessibilityIdentifier("youtube.musicbrainz.query")
            Button(action: controller.searchMusicBrainz) {
                Label("Search MusicBrainz", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.isBusy || YouTubeMusicSearchTitle.sanitized(controller.musicBrainzQuery).isEmpty)
            .accessibilityIdentifier("youtube.musicbrainz.search")

            switch controller.musicBrainzSearchState {
            case .idle:
                EmptyView()
            case .searching:
                ProgressView("Searching MusicBrainz…")
                    .accessibilityIdentifier("youtube.musicbrainz.loading")
            case .noResults:
                Text("No MusicBrainz recordings matched. You can keep editing manually.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("youtube.musicbrainz.empty")
            case .failed(let message):
                Text(message).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("youtube.musicbrainz.error")
            case .results:
                musicBrainzResults
            }
            if let message = controller.musicBrainzErrorMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("youtube.musicbrainz.releaseError")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var musicBrainzResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(controller.musicBrainzRecordings.enumerated()), id: \.offset) { index, recording in
                Button {
                    controller.selectMusicBrainzRecording(recording.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.title).font(.subheadline.weight(.medium))
                        if let artist = recording.artist { Text(artist).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(controller.isBusy)
                .accessibilityIdentifier("youtube.musicbrainz.recording.\(index)")
                if controller.selectedMusicBrainzRecordingID == recording.id {
                    ForEach(Array(recording.releases.enumerated()), id: \.offset) { releaseIndex, release in
                        Button {
                            controller.selectMusicBrainzRelease(release.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(release.title)
                                if let artist = release.artist { Text(artist).font(.caption).foregroundStyle(.secondary) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .disabled(controller.isBusy)
                        .accessibilityIdentifier("youtube.musicbrainz.release.\(releaseIndex)")
                        if controller.selectedMusicBrainzReleaseID == release.id {
                            selectedReleaseTracks
                        }
                    }
                    if recording.releases.isEmpty {
                        Text("No releases were included for this recording.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var selectedReleaseTracks: some View {
        if controller.isLoadingMusicBrainzRelease {
            ProgressView("Loading release tracks…")
                .accessibilityIdentifier("youtube.musicbrainz.releaseLoading")
        } else if let release = controller.selectedMusicBrainzRelease {
            ForEach(Array(release.tracks.enumerated()), id: \.offset) { index, track in
                Button {
                    controller.selectMusicBrainzTrack(track.id)
                } label: {
                    HStack {
                        Text(track.number.map(String.init) ?? "—")
                            .foregroundStyle(.secondary)
                        Text(track.title)
                        Spacer()
                        if controller.selectedMusicBrainzTrackID == track.id {
                            Image(systemName: "checkmark").accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(controller.isBusy)
                .accessibilityIdentifier("youtube.musicbrainz.track.\(index)")
                .accessibilityAddTraits(controller.selectedMusicBrainzTrackID == track.id ? .isSelected : [])
                .accessibilityValue(controller.selectedMusicBrainzTrackID == track.id ? "Selected" : "Not selected")
            }
            if release.tracks.isEmpty {
                Text("No tracks were available for this release.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if controller.isLoadingMusicBrainzArtwork {
                ProgressView("Loading cover art…")
                    .accessibilityIdentifier("youtube.musicbrainz.artworkLoading")
            } else if let message = controller.musicBrainzArtworkMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("youtube.musicbrainz.artworkStatus")
            }
        }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.footnote)
    }

    private var workStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                Text(statusText).accessibilityIdentifier("youtube.download.status")
            }
            if let progress = controller.transferProgress {
                Text("Attempt \(progress.attempt)")
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("youtube.download.attempt")
                if let fraction = progress.fractionCompleted {
                    ProgressView(value: fraction)
                        .accessibilityLabel("Audio download progress")
                        .accessibilityValue("\(Int(fraction * 100)) percent")
                    Text("\(Int(fraction * 100))%")
                        .font(.caption.monospacedDigit())
                        .accessibilityIdentifier("youtube.download.progress")
                } else {
                    ProgressView()
                        .accessibilityLabel("Audio download progress")
                        .accessibilityValue("Progress unavailable")
                    Text("Downloading audio…").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("youtube.download.progressIndeterminate")
                }
            }
            #if DEBUG
            if let fixtureStage = controller.fixtureStage {
                Text("Fixture stage: \(fixtureStage)")
                    .accessibilityIdentifier("youtube.download.fixtureStage")
                Button("Advance fixture") { controller.advanceFixture() }
                    .disabled(!controller.fixtureCanAdvance)
                    .accessibilityIdentifier("youtube.fixture.advance")
            }
            #endif
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).foregroundStyle(.red).accessibilityIdentifier("youtube.download.error")
            Button(controller.previewExists ? "Try download again" : "Try again", action: controller.retry)
                .disabled(controller.isBusy)
                .accessibilityIdentifier("youtube.download.retry")
            if controller.previewExists { Button("Edit link", action: controller.editURL) }
        }
    }

    private func savedReceipt(_ track: Track, cancelled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Saved to your library", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
            Text(track.title).accessibilityIdentifier("youtube.download.savedTrack")
            if let receipt = controller.savedReceipt {
                Text(receipt.format).font(.footnote).accessibilityIdentifier("youtube.download.actualFormat")
                if let bitrate = receipt.bitrate {
                    Text("\(Int(bitrate.rounded())) kb/s").font(.footnote).accessibilityIdentifier("youtube.download.actualBitrate")
                }
                if let bytes = receipt.exactBytes {
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(.footnote)
                        .accessibilityIdentifier("youtube.download.actualSize")
                } else if let bytes = receipt.approximateBytes {
                    Text("About \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))").font(.footnote)
                        .accessibilityIdentifier("youtube.download.actualSize")
                }
            }
            if cancelled { Text("The download was cancelled after this track was saved.").font(.footnote) }
            if let warning = controller.artworkWarning {
                Text(warning).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("youtube.download.artworkWarning")
            }
            Button("Play") { controller.play(track) }.accessibilityIdentifier("youtube.download.play")
            if let playbackMessage = controller.playbackMessage {
                Text(playbackMessage).font(.footnote).accessibilityIdentifier("youtube.download.playbackStatus")
            }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var isWorking: Bool {
        if case .working = controller.state { return true }
        if case .cancelling = controller.state { return true }
        return false
    }
    private var isCancelling: Bool { if case .cancelling = controller.state { return true }; return false }
    private var statusText: String {
        if case .cancelling = controller.state { return "Cancelling…" }
        if case .working(let message) = controller.state { return message }
        return ""
    }

    private static func durationText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
#endif
