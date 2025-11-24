//
//  PDFViewerApp.swift
//  PDFViewer
//
//  Created by steveyeh on 2025/7/10.
//

import SwiftUI

@main
struct PDFViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands { // We need to remove the default "New" menu item on macOS
            CommandGroup(replacing: .newItem) {}
        }
    }
}
