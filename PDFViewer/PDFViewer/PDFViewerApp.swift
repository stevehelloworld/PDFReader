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
        WindowGroup(id: "main") {
            ContentView()
        }
        #if os(macOS)
        .commands {
            ReopenMainWindowCommands()
            PDFViewerCommands()
        }
        #endif
    }
}

#if os(macOS)
struct ReaderCommands {
    let openFile: () -> Void
    let previousPage: () -> Void
    let nextPage: () -> Void
    let toggleSidebar: () -> Void
    let toggleSearch: () -> Void
    let toggleContinuous: () -> Void
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let zoomActualSize: () -> Void
    let zoomFitPage: () -> Void
    let zoomFitWidth: () -> Void
    let hasDocument: Bool
}

private struct ReaderCommandsKey: FocusedValueKey {
    typealias Value = ReaderCommands
}

extension FocusedValues {
    var readerCommands: ReaderCommands? {
        get { self[ReaderCommandsKey.self] }
        set { self[ReaderCommandsKey.self] = newValue }
    }
}

private struct PDFViewerCommands: Commands {
    @FocusedValue(\.readerCommands) private var commands

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "開啟檔案")) { commands?.openFile() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(commands == nil)
        }

        CommandMenu(String(localized: "導覽")) {
            Button(String(localized: "上一頁")) { commands?.previousPage() }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(commands?.hasDocument != true)
            Button(String(localized: "下一頁")) { commands?.nextPage() }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(commands?.hasDocument != true)
            Divider()
            Button(String(localized: "側邊欄")) { commands?.toggleSidebar() }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(commands?.hasDocument != true)
            Button(String(localized: "搜尋")) { commands?.toggleSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(commands?.hasDocument != true)
            Button(String(localized: "連續捲動")) { commands?.toggleContinuous() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(commands?.hasDocument != true)
        }

        CommandMenu(String(localized: "縮放")) {
            Button(String(localized: "放大")) { commands?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(commands?.hasDocument != true)
            Button(String(localized: "縮小")) { commands?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(commands?.hasDocument != true)
            Button(String(localized: "實際大小")) { commands?.zoomActualSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(commands?.hasDocument != true)
            Divider()
            Button(String(localized: "適應頁面")) { commands?.zoomFitPage() }
                .disabled(commands?.hasDocument != true)
            Button(String(localized: "適應寬度")) { commands?.zoomFitWidth() }
                .disabled(commands?.hasDocument != true)
        }
    }
}

private struct ReopenMainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button(String(localized: "重新開啟主視窗")) {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}
#endif
