//
//  ContentView.swift
//  vipod
//
//  Created by Alejandro on 1/10/26.
//

import SwiftUI

struct ContentView: View {
    let dependencies: AppDependencies?
    let startupFailed: Bool
    let retryStartup: () -> Void

    var body: some View {
        Group {
            #if DEBUG && os(iOS)
            if ProcessInfo.processInfo.arguments.contains("--youtube-poc"), let dependencies {
                let arguments = ProcessInfo.processInfo.arguments
                let initialURL = arguments.first(where: { $0.hasPrefix("--youtube-url=") })
                    .map { String($0.dropFirst("--youtube-url=".count)) } ?? ""
                YouTubeImportDiagnosticView(
                    library: dependencies.library,
                    playback: dependencies.playback,
                    initialURL: initialURL,
                    autoRun: arguments.contains("--youtube-poc-autorun") && YouTubeVideoURL(initialURL) != nil
                )
            } else if let dependencies {
                ClassicPlayerView(
                    library: dependencies.library,
                    collections: dependencies.collections,
                    playback: dependencies.playback,
                    artworkLoader: dependencies.artworkLoader,
                    audioConnection: dependencies.audioConnection,
                    deviceNameProvider: dependencies.deviceNameProvider
                )
            } else if startupFailed {
                StartupFailureView(retry: retryStartup)
            } else {
                ProgressView("Starting VIPOD…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #else
            if let dependencies {
                ClassicPlayerView(
                    library: dependencies.library,
                    collections: dependencies.collections,
                    playback: dependencies.playback,
                    artworkLoader: dependencies.artworkLoader,
                    audioConnection: dependencies.audioConnection,
                    deviceNameProvider: dependencies.deviceNameProvider
                )
            } else if startupFailed {
                StartupFailureView(retry: retryStartup)
            } else {
                ProgressView("Starting VIPOD…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG && os(iOS)
private struct YouTubeImportDiagnosticView: View {
    @State private var diagnostic: YouTubeImportDiagnostic
    @State private var didAutoRun = false
    private let autoRun: Bool

    init(library: LibraryController, playback: PlaybackController, initialURL: String, autoRun: Bool) {
        let diagnostic = YouTubeImportDiagnostic(library: library, playback: playback)
        diagnostic.urlText = initialURL
        _diagnostic = State(initialValue: diagnostic)
        self.autoRun = autoRun
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("YouTube Runtime Proof of Concept").font(.headline)
            TextField("https://www.youtube.com/watch?v=…", text: $diagnostic.urlText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("youtube.url")
            HStack {
                Button("Extract, Download & Import", action: diagnostic.run)
                    .disabled(diagnostic.isRunning)
                    .accessibilityIdentifier("youtube.run")
                if diagnostic.isRunning {
                    Button("Cancel", action: diagnostic.cancel)
                        .accessibilityIdentifier("youtube.cancel")
                }
            }
            Text(diagnostic.status)
                .font(.callout)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("youtube.status")
            if let latestLocalTrackTitle = diagnostic.latestLocalTrackTitle {
                Text("Saved local audio: \(latestLocalTrackTitle)")
                    .font(.callout)
                    .accessibilityIdentifier("youtube.savedTrack")
                Button("Play Saved Local Audio", action: diagnostic.playMostRecentLocalTrack)
                    .accessibilityIdentifier("youtube.playSavedLocal")
            }
            Spacer()
        }
        .padding(24)
        .task {
            await diagnostic.loadSavedLibrary()
            guard autoRun, !didAutoRun, YouTubeVideoURL(diagnostic.urlText) != nil else { return }
            didAutoRun = true
            await Task.yield()
            diagnostic.run()
        }
    }
}
#endif

private struct StartupFailureView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.largeTitle)
            Text("VIPOD could not access its music library storage.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Check available storage, then try again.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
