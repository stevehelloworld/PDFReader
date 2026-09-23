import SwiftUI
import PDFKit

// MARK: - Shared configuration applied to PDFView

enum PDFViewConfigurator {
    static func applyDisplayMode(
        to pdfView: PDFView,
        readingMode: ReadingMode,
        isContinuous: Bool
    ) {
        #if os(macOS)
        pdfView.pageBreakMargins = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        #else
        pdfView.pageBreakMargins = .zero
        #endif
        pdfView.displaysPageBreaks = isContinuous

        switch readingMode {
        case .singlePage:
            pdfView.displayMode = isContinuous ? .singlePageContinuous : .singlePage
            pdfView.displaysAsBook = false
            pdfView.displaysRTL = false
        case .twoPagesLTR:
            pdfView.displayMode = isContinuous ? .twoUpContinuous : .twoUp
            pdfView.displaysAsBook = true
            pdfView.displaysRTL = false
        case .twoPagesRTL:
            pdfView.displayMode = isContinuous ? .twoUpContinuous : .twoUp
            pdfView.displaysAsBook = true
            pdfView.displaysRTL = true
        }
    }

    static func applyZoom(
        to pdfView: PDFView,
        level: ZoomLevel,
        readingMode: ReadingMode,
        forceRecalculation: Bool = false
    ) {
        switch level {
        case .fitPage:
            if forceRecalculation {
                pdfView.autoScales = false
            }
            pdfView.autoScales = true
        case .fitWidth:
            pdfView.autoScales = false
            if let page = pdfView.currentPage {
                let pageBounds = page.bounds(for: .mediaBox)
                let viewWidth = max(pdfView.bounds.width, 1)
                let pageWidth = pageBounds.width
                let pageCount = readingMode.isBookMode ? CGFloat(2) : CGFloat(1)
                let interPageSpacing = readingMode.isBookMode ? CGFloat(16) : CGFloat(0)
                let availablePageWidth = max((viewWidth - interPageSpacing) / pageCount, 1)
                pdfView.scaleFactor = availablePageWidth / max(pageWidth, 1)
            }
        default:
            pdfView.autoScales = false
            if let scaleFactor = level.scaleFactor {
                pdfView.scaleFactor = scaleFactor
            }
        }
    }

    static func forceLayout(of pdfView: PDFView) {
        #if os(macOS)
        pdfView.needsLayout = true
        pdfView.layoutSubtreeIfNeeded()
        #else
        pdfView.setNeedsLayout()
        pdfView.layoutIfNeeded()
        #endif
    }

    static func applyAppearance(to pdfView: PDFView, appearance: ReadingAppearance) {
        #if os(macOS)
        let darkBG = NSColor(calibratedWhite: 0.12, alpha: 1)
        let sepiaBG = NSColor(calibratedRed: 0.96, green: 0.93, blue: 0.85, alpha: 1)
        let lightBG = NSColor.controlBackgroundColor
        #else
        let darkBG = UIColor(white: 0.12, alpha: 1)
        let sepiaBG = UIColor(red: 0.96, green: 0.93, blue: 0.85, alpha: 1)
        let lightBG = UIColor.systemBackground
        #endif

        switch appearance {
        case .automatic:
            pdfView.backgroundColor = lightBG
        case .light:
            pdfView.backgroundColor = lightBG
        case .sepia:
            pdfView.backgroundColor = sepiaBG
        case .night, .inverted:
            pdfView.backgroundColor = darkBG
        }
    }
}

// MARK: - Platform wrapper

struct PDFKitView: View {
    let document: PDFDocument
    @Binding var readingMode: ReadingMode
    @Binding var isContinuous: Bool
    @Binding var currentPage: Int
    @Binding var pageInputText: String
    @Binding var zoomLevel: ZoomLevel
    @Binding var appearance: ReadingAppearance
    var pendingSelection: PDFSelection?
    var onSelectionConsumed: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        GeometryReader { proxy in
            #if os(macOS)
            macOS_PDFKitView(
                document: document,
                viewportSize: proxy.size,
                readingMode: $readingMode,
                isContinuous: $isContinuous,
                currentPage: $currentPage,
                pageInputText: $pageInputText,
                zoomLevel: $zoomLevel,
                appearance: $appearance,
                pendingSelection: pendingSelection,
                onSelectionConsumed: onSelectionConsumed,
                onPrevious: onPrevious,
                onNext: onNext
            )
            #elseif os(iOS)
            iOS_PDFKitView(
                document: document,
                viewportSize: proxy.size,
                readingMode: $readingMode,
                isContinuous: $isContinuous,
                currentPage: $currentPage,
                pageInputText: $pageInputText,
                zoomLevel: $zoomLevel,
                appearance: $appearance,
                pendingSelection: pendingSelection,
                onSelectionConsumed: onSelectionConsumed
            )
            #endif
        }
    }
}

// MARK: - macOS

#if os(macOS)
struct macOS_PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let viewportSize: CGSize
    @Binding var readingMode: ReadingMode
    @Binding var isContinuous: Bool
    @Binding var currentPage: Int
    @Binding var pageInputText: String
    @Binding var zoomLevel: ZoomLevel
    @Binding var appearance: ReadingAppearance
    var pendingSelection: PDFSelection?
    var onSelectionConsumed: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.pageBreakMargins = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        let pan = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pdfView.addGestureRecognizer(pan)

        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        let c = context.coordinator
        c.parent = self

        // Document
        if c.appliedDocument !== document {
            nsView.document = document
            c.appliedDocument = document
            c.needsPageRestore = true
            c.appliedPage = -1
        }

        // Display mode
        let displayModeChanged = c.appliedMode != readingMode || c.appliedContinuous != isContinuous
        if displayModeChanged {
            c.displayRefreshID &+= 1
            let refreshID = c.displayRefreshID
            let requestedPage = currentPage
            c.isProgrammaticNavigation = true
            c.isProgrammaticSuppressed = true

            PDFViewConfigurator.applyDisplayMode(to: nsView, readingMode: readingMode, isContinuous: isContinuous)
            PDFViewConfigurator.forceLayout(of: nsView)
            if requestedPage >= 1,
               requestedPage <= document.pageCount,
               let targetPage = document.page(at: requestedPage - 1) {
                nsView.go(to: targetPage)
                c.appliedPage = requestedPage
                c.needsPageRestore = false
            }
            PDFViewConfigurator.applyZoom(
                to: nsView,
                level: zoomLevel,
                readingMode: readingMode,
                forceRecalculation: true
            )
            c.appliedMode = readingMode
            c.appliedContinuous = isContinuous
            c.appliedZoom = zoomLevel
            c.appliedViewportSize = viewportSize

            // PDFKit finishes rebuilding its internal page views on the next run loop.
            // Reassert the requested page and zoom once, discarding stale rapid toggles.
            DispatchQueue.main.async {
                guard c.displayRefreshID == refreshID else { return }
                PDFViewConfigurator.forceLayout(of: nsView)
                if requestedPage >= 1,
                   requestedPage <= document.pageCount,
                   let targetPage = document.page(at: requestedPage - 1) {
                    nsView.go(to: targetPage)
                    c.appliedPage = requestedPage
                }
                PDFViewConfigurator.applyZoom(
                    to: nsView,
                    level: zoomLevel,
                    readingMode: readingMode,
                    forceRecalculation: true
                )
                c.isProgrammaticNavigation = false
                c.isProgrammaticSuppressed = false
            }
        }

        // Zoom (diff only)
        if !displayModeChanged,
           (c.appliedZoom != zoomLevel || c.appliedViewportSize != viewportSize) {
            PDFViewConfigurator.applyZoom(to: nsView, level: zoomLevel, readingMode: readingMode)
            c.appliedZoom = zoomLevel
            c.appliedViewportSize = viewportSize
        }

        // Appearance
        if c.appliedAppearance != appearance {
            PDFViewConfigurator.applyAppearance(to: nsView, appearance: appearance)
            c.appliedAppearance = appearance
        }

        // Page navigation
        if currentPage >= 1,
           currentPage <= document.pageCount,
           let targetPage = document.page(at: currentPage - 1) {
            let pageDiffers = c.appliedPage != currentPage
            if c.needsPageRestore || (pageDiffers && !c.isProgrammaticSuppressed) {
                c.isProgrammaticNavigation = true
                nsView.go(to: targetPage)
                c.appliedPage = currentPage
                c.needsPageRestore = false
                DispatchQueue.main.async {
                    c.isProgrammaticNavigation = false
                }
            }
        }

        // Search selection
        if let selection = pendingSelection {
            nsView.currentSelection = selection
            nsView.go(to: selection)
            DispatchQueue.main.async {
                onSelectionConsumed()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        var parent: macOS_PDFKitView
        weak var appliedDocument: PDFDocument?
        var appliedMode: ReadingMode?
        var appliedContinuous: Bool?
        var appliedZoom: ZoomLevel?
        var appliedViewportSize: CGSize?
        var appliedAppearance: ReadingAppearance?
        var appliedPage: Int = -1
        var needsPageRestore = false
        var isProgrammaticNavigation = false
        var displayRefreshID = 0
        /// Brief suppress after mode change so PDFKit's internal page adjust doesn't fight us.
        var isProgrammaticSuppressed = false
        private var startPoint: NSPoint?

        init(parent: macOS_PDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPDFPage = pdfView.currentPage,
                  let document = pdfView.document else { return }

            let newPage = document.index(for: currentPDFPage) + 1
            guard newPage != parent.currentPage else {
                appliedPage = newPage
                return
            }
            guard !isProgrammaticNavigation && !isProgrammaticSuppressed else {
                appliedPage = newPage
                return
            }

            DispatchQueue.main.async {
                self.parent.currentPage = newPage
                self.parent.pageInputText = "\(newPage)"
                self.appliedPage = newPage
            }
        }

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            // Only use pan for page-turns in non-continuous discrete page modes.
            guard !parent.isContinuous else { return }
            guard let view = gesture.view as? PDFView else { return }

            switch gesture.state {
            case .began:
                startPoint = gesture.location(in: view)
            case .ended:
                guard let start = startPoint else { return }
                let end = gesture.location(in: view)
                let dx = end.x - start.x
                let dy = end.y - start.y
                guard abs(dx) > abs(dy), abs(dx) > 60 else {
                    startPoint = nil
                    return
                }

                let rtl = parent.readingMode.isRTL
                if dx < 0 {
                    if rtl { if view.canGoToPreviousPage { view.goToPreviousPage(nil) } }
                    else { if view.canGoToNextPage { view.goToNextPage(nil) } }
                } else {
                    if rtl { if view.canGoToNextPage { view.goToNextPage(nil) } }
                    else { if view.canGoToPreviousPage { view.goToPreviousPage(nil) } }
                }
                startPoint = nil
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: NSGestureRecognizer
        ) -> Bool {
            true
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
#endif

// MARK: - iOS

#if os(iOS)
struct iOS_PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let viewportSize: CGSize
    @Binding var readingMode: ReadingMode
    @Binding var isContinuous: Bool
    @Binding var currentPage: Int
    @Binding var pageInputText: String
    @Binding var zoomLevel: ZoomLevel
    @Binding var appearance: ReadingAppearance
    var pendingSelection: PDFSelection?
    var onSelectionConsumed: () -> Void

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.pageBreakMargins = .zero

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        let left = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        left.direction = .left
        pdfView.addGestureRecognizer(left)

        let right = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        right.direction = .right
        pdfView.addGestureRecognizer(right)

        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        let c = context.coordinator
        c.parent = self

        if c.appliedDocument !== document {
            uiView.document = document
            c.appliedDocument = document
            c.needsPageRestore = true
            c.appliedPage = -1
        }

        let displayModeChanged = c.appliedMode != readingMode || c.appliedContinuous != isContinuous
        if displayModeChanged {
            c.displayRefreshID &+= 1
            let refreshID = c.displayRefreshID
            let requestedPage = currentPage
            c.isProgrammaticNavigation = true

            PDFViewConfigurator.applyDisplayMode(to: uiView, readingMode: readingMode, isContinuous: isContinuous)
            PDFViewConfigurator.forceLayout(of: uiView)
            if requestedPage >= 1,
               requestedPage <= document.pageCount,
               let targetPage = document.page(at: requestedPage - 1) {
                uiView.go(to: targetPage)
                c.appliedPage = requestedPage
                c.needsPageRestore = false
            }
            PDFViewConfigurator.applyZoom(
                to: uiView,
                level: zoomLevel,
                readingMode: readingMode,
                forceRecalculation: true
            )
            c.appliedMode = readingMode
            c.appliedContinuous = isContinuous
            c.appliedZoom = zoomLevel
            c.appliedViewportSize = viewportSize

            DispatchQueue.main.async {
                guard c.displayRefreshID == refreshID else { return }
                PDFViewConfigurator.forceLayout(of: uiView)
                if requestedPage >= 1,
                   requestedPage <= document.pageCount,
                   let targetPage = document.page(at: requestedPage - 1) {
                    uiView.go(to: targetPage)
                    c.appliedPage = requestedPage
                }
                PDFViewConfigurator.applyZoom(
                    to: uiView,
                    level: zoomLevel,
                    readingMode: readingMode,
                    forceRecalculation: true
                )
                c.isProgrammaticNavigation = false
            }
        }

        if !displayModeChanged,
           (c.appliedZoom != zoomLevel || c.appliedViewportSize != viewportSize) {
            PDFViewConfigurator.applyZoom(to: uiView, level: zoomLevel, readingMode: readingMode)
            c.appliedZoom = zoomLevel
            c.appliedViewportSize = viewportSize
        }

        if c.appliedAppearance != appearance {
            PDFViewConfigurator.applyAppearance(to: uiView, appearance: appearance)
            c.appliedAppearance = appearance
        }

        if currentPage >= 1,
           currentPage <= document.pageCount,
           let targetPage = document.page(at: currentPage - 1) {
            let pageDiffers = c.appliedPage != currentPage
            if c.needsPageRestore || (pageDiffers && !c.isProgrammaticNavigation) {
                c.isProgrammaticNavigation = true
                uiView.go(to: targetPage)
                c.appliedPage = currentPage
                c.needsPageRestore = false
                DispatchQueue.main.async {
                    c.isProgrammaticNavigation = false
                }
            }
        }

        if let selection = pendingSelection {
            uiView.currentSelection = selection
            uiView.go(to: selection)
            DispatchQueue.main.async {
                onSelectionConsumed()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: iOS_PDFKitView
        weak var appliedDocument: PDFDocument?
        var appliedMode: ReadingMode?
        var appliedContinuous: Bool?
        var appliedZoom: ZoomLevel?
        var appliedViewportSize: CGSize?
        var appliedAppearance: ReadingAppearance?
        var appliedPage: Int = -1
        var needsPageRestore = false
        var isProgrammaticNavigation = false
        var displayRefreshID = 0

        init(parent: iOS_PDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPDFPage = pdfView.currentPage,
                  let document = pdfView.document else { return }

            let newPage = document.index(for: currentPDFPage) + 1
            guard newPage != parent.currentPage else {
                appliedPage = newPage
                return
            }
            guard !isProgrammaticNavigation else {
                appliedPage = newPage
                return
            }

            DispatchQueue.main.async {
                self.parent.currentPage = newPage
                self.parent.pageInputText = "\(newPage)"
                self.appliedPage = newPage
            }
        }

        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            guard !parent.isContinuous else { return }
            guard let view = gesture.view as? PDFView else { return }
            let rtl = parent.readingMode.isRTL

            if gesture.direction == .left {
                if rtl { if view.canGoToPreviousPage { view.goToPreviousPage(nil) } }
                else { if view.canGoToNextPage { view.goToNextPage(nil) } }
            } else if gesture.direction == .right {
                if rtl { if view.canGoToNextPage { view.goToNextPage(nil) } }
                else { if view.canGoToPreviousPage { view.goToPreviousPage(nil) } }
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - Document Picker (in-place, not copy)

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: false)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
    }
}
#endif
