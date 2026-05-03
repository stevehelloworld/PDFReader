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
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "開啟檔案")) {
                    NotificationCenter.default.post(name: .openPDFFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            
            CommandMenu(String(localized: "縮放")) {
                Button(String(localized: "放大")) {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button(String(localized: "縮小")) {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button(String(localized: "實際大小")) {
                    NotificationCenter.default.post(name: .zoomActualSize, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
                
                Divider()
                
                Button(String(localized: "適應頁面")) {
                    NotificationCenter.default.post(name: .zoomFitPage, object: nil)
                }
                
                Button(String(localized: "適應寬度")) {
                    NotificationCenter.default.post(name: .zoomFitWidth, object: nil)
                }
            }
        }
        #endif
    }
}

// MARK: - App Command Notifications
extension Notification.Name {
    static let openPDFFile = Notification.Name("openPDFFile")
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomActualSize = Notification.Name("zoomActualSize")
    static let zoomFitPage = Notification.Name("zoomFitPage")
    static let zoomFitWidth = Notification.Name("zoomFitWidth")
}
