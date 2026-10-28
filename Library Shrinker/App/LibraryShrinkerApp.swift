//
//  Library_ShrinkerApp.swift
//  Library Shrinker
//
//  Created by Guo Siqi on 7/8/26.
//

import SwiftUI

@main
struct LibraryShrinkerApp: App {
    init() {
        ContinuousCompressionCoordinator.shared.registerLaunchHandlers()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
