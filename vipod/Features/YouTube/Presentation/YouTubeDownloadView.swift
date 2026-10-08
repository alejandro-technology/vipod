import SwiftUI

#if os(iOS)
struct YouTubeDownloadView: View {
    @Bindable private var controller: YouTubeDownloadController
    @Environment(\.dismiss) private var dismiss

    init(controller: YouTubeDownloadController) {
        self.controller = controller
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Download one video") {
                    TextField("YouTube video URL", text: $controller.urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("youtube.download.url")
                    if isWorking {
                        HStack {
                            ProgressView()
                            Text(statusText).accessibilityIdentifier("youtube.download.status")
                        }
                        Button("Cancel", action: controller.cancel)
                            .disabled(isCancelling)
                            .accessibilityIdentifier("youtube.download.cancel")
                    } else {
                        Button("Download", action: controller.submit)
                            .disabled(controller.isBusy || controller.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("youtube.download.submit")
                    }
                }
                switch controller.state {
                case .failed(let message):
                    Section {
                        Text(message).foregroundStyle(.red).accessibilityIdentifier("youtube.download.error")
                        Button("Edit link", action: controller.editURL)
                        Button("Try again", action: controller.retry)
                            .disabled(controller.isBusy || controller.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                case .cancelled:
                    Section { Text("Download stopped. Any track already saved remains in your library.") }
                case .completed(let track, let cancellationArrivedAfterCommit):
                    Section("Saved to your library") {
                        Text(track.title).accessibilityIdentifier("youtube.download.savedTrack")
                        if cancellationArrivedAfterCommit {
                            Text("The download was cancelled after this track was saved.")
                        }
                        Button("Play") { controller.play(track) }
                            .accessibilityIdentifier("youtube.download.play")
                        if let playbackMessage = controller.playbackMessage {
                            Text(playbackMessage).accessibilityIdentifier("youtube.download.playbackStatus")
                        }
                    }
                default: EmptyView()
                }
            }
            .navigationTitle("YouTube Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("youtube.download.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var isWorking: Bool {
        switch controller.state {
        case .working, .cancelling: true
        default: false
        }
    }

    private var statusText: String {
        if case .cancelling = controller.state { return "Cancelling…" }
        if case .working(let message) = controller.state { return message }
        return ""
    }

    private var isCancelling: Bool {
        if case .cancelling = controller.state { return true }
        return false
    }
}
#endif
