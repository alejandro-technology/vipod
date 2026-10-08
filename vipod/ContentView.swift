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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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
