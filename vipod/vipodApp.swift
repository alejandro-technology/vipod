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
        }
    }
}
