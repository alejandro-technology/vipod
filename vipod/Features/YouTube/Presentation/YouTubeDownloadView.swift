import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
struct YouTubeDownloadView: View {
    private enum MusicBrainzStep: Int {
        case recordings = 1
        case releases
        case tracks

        var title: String {
            switch self {
            case .recordings: "Choose a recording"
            case .releases: "Choose an album"
            case .tracks: "Choose a track"
            }
        }
    }

    @Bindable private var controller: YouTubeDownloadController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("vipod.theme") private var themePreference = "black"
    @State private var musicBrainzStep: MusicBrainzStep = .recordings

    private var colorScheme: ColorScheme { themePreference == "white" ? .light : .dark }

    init(controller: YouTubeDownloadController) { self.controller = controller }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    linkEntry
                    if let preview = controller.retainedPreview {
                        previewCard(preview)
                        if isWorking { workStatus }
                        musicBrainzSearch
                        metadataEditor
                    } else if isWorking {
                        workStatus
                    }
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
        .preferredColorScheme(colorScheme)
        .onChange(of: controller.musicBrainzQuery) { _, _ in
            musicBrainzStep = .recordings
        }
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
            Text("Find a recording with MusicBrainz")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("youtube.musicbrainz.heading")
            TextField("Search title", text: $controller.musicBrainzQuery)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .disabled(controller.isBusy)
                .accessibilityLabel("MusicBrainz search title")
                .accessibilityIdentifier("youtube.musicbrainz.query")
            Button(action: searchMusicBrainz) {
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

    private func searchMusicBrainz() {
        musicBrainzStep = .recordings
        controller.searchMusicBrainz()
    }

    private var musicBrainzResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if musicBrainzStep != .recordings {
                    Button(action: goToPreviousMusicBrainzStep) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(musicBrainzStep == .tracks ? "Back to albums" : "Back to recordings")
                    .accessibilityIdentifier("youtube.musicbrainz.back")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Step \(musicBrainzStep.rawValue) of 3")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("youtube.musicbrainz.stepCount")
                    Text(musicBrainzStep.title)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("youtube.musicbrainz.stepTitle")
                }
                Spacer()
            }

            switch musicBrainzStep {
            case .recordings:
                recordingOptions
            case .releases:
                releaseOptions
            case .tracks:
                trackOptions
            }
        }
    }

    private var recordingOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose the matching song recording. Artist, genre, original release date and album count can help distinguish versions.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(controller.musicBrainzRecordings.enumerated()), id: \.offset) { index, recording in
                let selected = controller.selectedMusicBrainzRecordingID == recording.id
                Button {
                    controller.selectMusicBrainzRecording(recording.id)
                    musicBrainzStep = .releases
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recording.title).font(.subheadline.weight(.semibold))
                            Text(recording.artist ?? "Artist unavailable")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(recordingInfo(recording))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selected ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.25)))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(controller.isBusy)
                .accessibilityIdentifier("youtube.musicbrainz.recording.\(index)")
                .accessibilityLabel("\(recording.title), \(recording.artist ?? "Artist unavailable"), \(recordingInfo(recording))")
                .accessibilityValue(selected ? "Selected" : "Not selected")
            }
        }
    }

    @ViewBuilder
    private var releaseOptions: some View {
        if let recording = selectedMusicBrainzRecording {
            VStack(alignment: .leading, spacing: 8) {
                selectedMusicBrainzSummary(title: "Recording", value: recording.title, detail: recording.artist)
                Text("Choose an album edition. Release date and track count help identify the right pressing.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(recording.releases.enumerated()), id: \.offset) { index, release in
                    let selected = controller.selectedMusicBrainzReleaseID == release.id
                    Button {
                        controller.selectMusicBrainzRelease(release.id)
                        musicBrainzStep = .tracks
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(release.title).font(.subheadline.weight(.semibold))
                                Text(release.artist ?? "Album artist unavailable")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(releaseInfo(release))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.25)))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.isBusy)
                    .accessibilityIdentifier("youtube.musicbrainz.release.\(index)")
                    .accessibilityLabel("\(release.title), \(release.artist ?? "Album artist unavailable"), \(releaseInfo(release))")
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                }
                if recording.releases.isEmpty {
                    Text("No releases were included for this recording.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Choose a recording first.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trackOptions: some View {
        if let release = controller.selectedMusicBrainzRelease {
            VStack(alignment: .leading, spacing: 8) {
                selectedMusicBrainzSummary(title: "Album", value: release.title, detail: release.artist)
                if let date = release.date {
                    Text("Released \(date)").font(.caption).foregroundStyle(.secondary)
                }
                if let genre = release.genre {
                    Text("Genre: \(genre)").font(.caption).foregroundStyle(.secondary)
                }
                if controller.isLoadingMusicBrainzArtwork {
                    ProgressView("Loading cover art…")
                        .accessibilityIdentifier("youtube.musicbrainz.artworkLoading")
                } else if let message = controller.musicBrainzArtworkMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("youtube.musicbrainz.artworkStatus")
                }
                Text("Choose the track to apply its title, artist and track/disc number to the editable metadata.")
                    .font(.caption).foregroundStyle(.secondary)
                releaseTracks(release)
            }
        } else if controller.isLoadingMusicBrainzRelease {
            ProgressView("Loading album tracks…")
                .accessibilityIdentifier("youtube.musicbrainz.releaseLoading")
        } else if controller.musicBrainzErrorMessage != nil {
            Text("Album details could not be loaded. Go back and choose another edition.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Choose an album first.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func releaseTracks(_ release: YouTubeMusicReleaseDetails) -> some View {
        Group {
            if release.tracks.isEmpty {
                Text("No tracks were available for this release.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(release.tracks.enumerated()), id: \.offset) { index, track in
                    let selected = controller.selectedMusicBrainzTrackID == track.id
                    Button {
                        controller.selectMusicBrainzTrack(track.id)
                    } label: {
                        HStack(spacing: 10) {
                            Text(track.number.map(String.init) ?? "—")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(minWidth: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title).font(.subheadline.weight(.medium))
                                Text(trackInfo(track, in: release))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor).accessibilityHidden(true)
                            }
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.isBusy)
                    .accessibilityIdentifier("youtube.musicbrainz.track.\(index)")
                    .accessibilityLabel("\(track.title), \(trackInfo(track, in: release))")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                }
            }
        }
    }

    private var selectedMusicBrainzRecording: YouTubeMusicRecording? {
        controller.musicBrainzRecordings.first { $0.id == controller.selectedMusicBrainzRecordingID }
    }

    private func selectedMusicBrainzSummary(title: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func recordingInfo(_ recording: YouTubeMusicRecording) -> String {
        var details: [String] = []
        if let genre = recording.genre { details.append(genre) }
        if let date = recording.firstReleaseDate { details.append("First released \(date)") }
        details.append(recording.releases.count == 1 ? "1 album edition" : "\(recording.releases.count) album editions")
        return details.joined(separator: " · ")
    }

    private func releaseInfo(_ release: YouTubeMusicReleaseSummary) -> String {
        var details: [String] = []
        if let date = release.date { details.append(date) }
        if let count = release.trackCount { details.append(count == 1 ? "1 track" : "\(count) tracks") }
        return details.isEmpty ? "Release details unavailable" : details.joined(separator: " · ")
    }

    private func trackInfo(_ track: YouTubeMusicTrack, in release: YouTubeMusicReleaseDetails) -> String {
        var details: [String] = []
        if let artist = track.artist { details.append(artist) }
        if let number = track.number {
            details.append(track.numberTotal.map { "Track \(number) of \($0)" } ?? "Track \(number)")
        }
        if let disc = track.discNumber {
            details.append(release.discTotal.map { "Disc \(disc) of \($0)" } ?? "Disc \(disc)")
        }
        return details.isEmpty ? "Track details unavailable" : details.joined(separator: " · ")
    }

    private func goToPreviousMusicBrainzStep() {
        switch musicBrainzStep {
        case .recordings:
            break
        case .releases:
            musicBrainzStep = .recordings
        case .tracks:
            musicBrainzStep = .releases
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
                    let percentage = Int(fraction * 100)
                    ProgressView(value: fraction)
                        .accessibilityLabel("Audio download progress")
                        .accessibilityValue(progress.isEstimated ? "Approximately \(percentage) percent" : "\(percentage) percent")
                    Text(progress.isEstimated ? "~\(percentage)%" : "\(percentage)%")
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("youtube.download.workStatus")
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).foregroundStyle(.primary).accessibilityIdentifier("youtube.download.error")
            Button(controller.previewExists ? "Try download again" : "Try again", action: controller.retry)
                .disabled(controller.isBusy)
                .accessibilityIdentifier("youtube.download.retry")
            if controller.previewExists { Button("Edit link", action: controller.editURL) }
        }
    }

    private func savedReceipt(_ track: Track, cancelled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Saved to your library", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.primary)
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
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
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
