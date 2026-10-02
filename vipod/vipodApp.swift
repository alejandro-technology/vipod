//
//  vipodApp.swift
//  vipod
//
//  Created by Alejandro on 1/10/26.
//

import SwiftUI

@MainActor
@main
struct vipodApp: App {
    @State private var composition = AppComposition()

    var body: some Scene {
        WindowGroup {
            ContentView(
                dependencies: composition.dependencies,
                startupFailed: composition.didFailToStart,
                retryStartup: composition.retryStartup
            )
            #if os(macOS)
                .portraitPlayerWindow()
            #endif
        }
        #if os(macOS)
        .defaultSize(width: PortraitPlayerWindow.defaultSize.width, height: PortraitPlayerWindow.defaultSize.height)
        .windowResizability(.contentMinSize)
        #endif
    }
}
