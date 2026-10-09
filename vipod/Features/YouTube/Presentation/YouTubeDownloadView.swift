import SwiftUI

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
                    if let preview = controller.retainedPreview { previewCard(preview) }
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
                if let thumbnailURL = preview.thumbnailURL {
                    AsyncImage(url: thumbnailURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8).fill(.quaternary).overlay { ProgressView() }
                    }
                    .frame(width: 116, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Video thumbnail; not verified album artwork")
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(preview.effectiveMetadata.title).font(.headline).accessibilityIdentifier("youtube.preview.title")
                    if let artist = preview.effectiveMetadata.artist { Text(artist).font(.subheadline) }
                    if let album = preview.effectiveMetadata.album { Text(album).font(.subheadline).foregroundStyle(.secondary) }
                    if let albumArtist = preview.effectiveMetadata.albumArtist { Text("Album artist: \(albumArtist)").font(.caption).foregroundStyle(.secondary) }
                    if let channel = preview.channel { Text("Source: \(channel)").font(.caption).foregroundStyle(.secondary) }
                }
            }
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
    private func metadataRows(_ preview: YouTubeVideoPreview) -> some View {
        let metadata = preview.effectiveMetadata
        if let duration = preview.duration { metadataRow("Duration", value: Self.durationText(duration)) }
        if let date = metadata.releaseDate { metadataRow("Release date", value: date) }
        if let genre = metadata.genre { metadataRow("Genre", value: genre) }
        if let number = metadata.trackNumber { metadataRow("Track", value: metadata.trackNumberTotal.map { "\(number)/\($0)" } ?? "\(number)") }
        if let number = metadata.discNumber { metadataRow("Disc", value: metadata.discNumberTotal.map { "\(number)/\($0)" } ?? "\(number)") }
        if let uploadDate = preview.uploadDate { metadataRow("Video upload date", value: uploadDate) }
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
