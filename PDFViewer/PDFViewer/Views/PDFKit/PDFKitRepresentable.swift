import SwiftUI
import PDFKit

final class PDFViewPageSource {
    private weak var pdfView: PDFView?
    private weak var rememberedDocument: PDFDocument?
    private var rememberedPage: Int?
    private weak var protectedDocument: PDFDocument?
    private var protectedPage: Int?

    func attach(_ pdfView: PDFView) {
        self.pdfView = pdfView
    }

    func detach(_ pdfView: PDFView) {
        if self.pdfView === pdfView {
            if let document = pdfView.document,
               let pageNumber = currentPageNumber(in: document) {
                remember(pageNumber: pageNumber, in: document)
            }
            self.pdfView = nil
        }
    }

    func currentPageNumber(in document: PDFDocument) -> Int? {
        if let pdfView,
           pdfView.document === document,
           let pageNumber = Self.pageNumber(in: pdfView, document: document) {
            if shouldIgnorePageChange(pageNumber: pageNumber, in: document) {
                return protectedPage
            }
            remember(pageNumber: pageNumber, in: document)
            return pageNumber
        }
        return rememberedPageNumber(in: document)
    }

    func rememberedPageNumber(in document: PDFDocument) -> Int? {
        guard rememberedDocument === document,
              let rememberedPage,
              (1...document.pageCount).contains(rememberedPage) else { return nil }
        return rememberedPage
    }

    func remember(pageNumber: Int, in document: PDFDocument) {
        guard (1...document.pageCount).contains(pageNumber) else { return }
        rememberedDocument = document
        rememberedPage = pageNumber
    }

    func protect(pageNumber: Int, in document: PDFDocument) {
        guard (1...document.pageCount).contains(pageNumber) else { return }
        remember(pageNumber: pageNumber, in: document)
        protectedDocument = document
        protectedPage = pageNumber
    }

    func clearPageProtection(in document: PDFDocument) {
        guard protectedDocument === document else { return }
        protectedDocument = nil
        protectedPage = nil
    }

    func protectedPageNumber(in document: PDFDocument) -> Int? {
        guard protectedDocument === document,
              let protectedPage,
              (1...document.pageCount).contains(protectedPage) else { return nil }
        return protectedPage
    }

    func shouldIgnorePageChange(pageNumber: Int, in document: PDFDocument) -> Bool {
        guard let protectedPage = protectedPageNumber(in: document) else { return false }
        return pageNumber != protectedPage
    }

    private static func pageNumber(in pdfView: PDFView, document: PDFDocument) -> Int? {
        guard let page = pdfView.currentPage else { return nil }
        let index = document.index(for: page)
        guard (0..<document.pageCount).contains(index) else { return nil }
        return index + 1
    }
}

// MARK: - Shared configuration applied to PDFView

enum PDFViewConfigurator {
    static func currentPageNumber(in pdfView: PDFView, fallback: Int) -> Int {
        guard let document = pdfView.document,
              let page = pdfView.currentPage else { return fallback }
        let index = document.index(for: page)
        guard (0..<document.pageCount).contains(index) else { return fallback }
        return index + 1
    }

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
        pdfView.layoutDocumentView()
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
    let pageSource: PDFViewPageSource
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
                pageSource: pageSource,
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
                pageSource: pageSource,
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
            #endif
        }
    }
}

// MARK: - macOS

#if os(macOS)
struct macOS_PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let pageSource: PDFViewPageSource
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
        pageSource.attach(pdfView)
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
        let rememberedPageBeforeUpdate = pageSource.rememberedPageNumber(in: document)

        // Document
        let documentChanged = c.appliedDocument !== document
        if documentChanged {
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
            let fallbackPage = rememberedPageBeforeUpdate ?? (c.appliedPage > 0 ? c.appliedPage : currentPage)
            let requestedPage = documentChanged
                ? fallbackPage
                : PDFViewConfigurator.currentPageNumber(in: nsView, fallback: fallbackPage)
            c.isProgrammaticNavigation = true
            c.isProgrammaticSuppressed = true
            pageSource.protect(pageNumber: requestedPage, in: document)

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
                guard !c.isDismantled, c.displayRefreshID == refreshID else { return }
                PDFViewConfigurator.forceLayout(of: nsView)
                if requestedPage >= 1,
                   requestedPage <= document.pageCount,
                   let targetPage = document.page(at: requestedPage - 1) {
                    if pageSource.protectedPageNumber(in: document) == requestedPage {
                        nsView.go(to: targetPage)
                        currentPage = requestedPage
                        pageInputText = "\(requestedPage)"
                        c.appliedPage = requestedPage
                        pageSource.remember(pageNumber: requestedPage, in: document)
                    }
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

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.isDismantled = true
        coordinator.parent.pageSource.detach(nsView)
        NotificationCenter.default.removeObserver(
            coordinator,
            name: .PDFViewPageChanged,
            object: nsView
        )
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
        var isDismantled = false
        private var startPoint: NSPoint?

        init(parent: macOS_PDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard !isDismantled,
                  let pdfView = notification.object as? PDFView,
                  let currentPDFPage = pdfView.currentPage,
                  let document = pdfView.document else { return }

            let newPage = document.index(for: currentPDFPage) + 1
            guard (1...document.pageCount).contains(newPage) else { return }
            if parent.pageSource.shouldIgnorePageChange(pageNumber: newPage, in: document) {
                appliedPage = parent.pageSource.protectedPageNumber(in: document) ?? parent.currentPage
                return
            }
            parent.pageSource.remember(pageNumber: newPage, in: document)
            guard newPage != parent.currentPage else {
                appliedPage = newPage
                return
            }
            guard !isProgrammaticNavigation && !isProgrammaticSuppressed else {
                appliedPage = newPage
                return
            }

            publishPageChange(newPage)
        }

        private func publishPageChange(_ page: Int) {
            guard !isDismantled else { return }
            if Thread.isMainThread {
                guard !isProgrammaticNavigation && !isProgrammaticSuppressed else { return }
                // Keep SwiftUI's page state current before a mode switch rebuilds PDFView.
                parent.currentPage = page
                parent.pageInputText = "\(page)"
                appliedPage = page
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.publishPageChange(page)
                }
            }
        }

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            // Only use pan for page-turns in non-continuous discrete page modes.
            guard let view = gesture.view as? PDFView,
                  let document = view.document else { return }
            if gesture.state == .began {
                parent.pageSource.clearPageProtection(in: document)
            }
            guard !parent.isContinuous else { return }

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
                    if rtl { parent.onPrevious() }
                    else { parent.onNext() }
                } else {
                    if rtl { parent.onNext() }
                    else { parent.onPrevious() }
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
    let pageSource: PDFViewPageSource
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

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pageSource.attach(pdfView)
        pdfView.autoScales = true
        pdfView.pageBreakMargins = .zero

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        let horizontalPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleHorizontalPan(_:))
        )
        horizontalPan.delegate = context.coordinator
        horizontalPan.cancelsTouchesInView = false
        horizontalPan.maximumNumberOfTouches = 1
        pdfView.addGestureRecognizer(horizontalPan)

        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        let c = context.coordinator
        c.parent = self
        let rememberedPageBeforeUpdate = pageSource.rememberedPageNumber(in: document)

        let documentChanged = c.appliedDocument !== document
        if documentChanged {
            uiView.document = document
            c.appliedDocument = document
            c.needsPageRestore = true
            c.appliedPage = -1
        }

        let displayModeChanged = c.appliedMode != readingMode || c.appliedContinuous != isContinuous
        if displayModeChanged {
            c.displayRefreshID &+= 1
            let refreshID = c.displayRefreshID
            let fallbackPage = rememberedPageBeforeUpdate ?? (c.appliedPage > 0 ? c.appliedPage : currentPage)
            let requestedPage = documentChanged
                ? fallbackPage
                : PDFViewConfigurator.currentPageNumber(in: uiView, fallback: fallbackPage)
            c.isProgrammaticNavigation = true
            pageSource.protect(pageNumber: requestedPage, in: document)

            PDFViewConfigurator.applyDisplayMode(to: uiView, readingMode: readingMode, isContinuous: isContinuous)
            uiView.usePageViewController(!isContinuous, withViewOptions: nil)
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
                guard !c.isDismantled, c.displayRefreshID == refreshID else { return }
                PDFViewConfigurator.forceLayout(of: uiView)
                if requestedPage >= 1,
                   requestedPage <= document.pageCount,
                   let targetPage = document.page(at: requestedPage - 1) {
                    if pageSource.protectedPageNumber(in: document) == requestedPage {
                        uiView.go(to: targetPage)
                        currentPage = requestedPage
                        pageInputText = "\(requestedPage)"
                        c.appliedPage = requestedPage
                        pageSource.remember(pageNumber: requestedPage, in: document)
                    }
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

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.isDismantled = true
        coordinator.parent.pageSource.detach(uiView)
        NotificationCenter.default.removeObserver(
            coordinator,
            name: .PDFViewPageChanged,
            object: uiView
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
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
        var isDismantled = false
        private var swipeStartPage: Int?

        init(parent: iOS_PDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard !isDismantled,
                  let pdfView = notification.object as? PDFView,
                  let currentPDFPage = pdfView.currentPage,
                  let document = pdfView.document else { return }

            let newPage = document.index(for: currentPDFPage) + 1
            guard (1...document.pageCount).contains(newPage) else { return }
            if parent.pageSource.shouldIgnorePageChange(pageNumber: newPage, in: document) {
                appliedPage = parent.pageSource.protectedPageNumber(in: document) ?? parent.currentPage
                return
            }
            parent.pageSource.remember(pageNumber: newPage, in: document)
            guard newPage != parent.currentPage else {
                appliedPage = newPage
                return
            }
            guard !isProgrammaticNavigation else {
                appliedPage = newPage
                return
            }

            publishPageChange(newPage)
        }

        private func publishPageChange(_ page: Int) {
            guard !isDismantled else { return }
            if Thread.isMainThread {
                guard !isProgrammaticNavigation else { return }
                // Keep SwiftUI's page state current before a mode switch rebuilds PDFView.
                parent.currentPage = page
                parent.pageInputText = "\(page)"
                appliedPage = page
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.publishPageChange(page)
                }
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            let velocity = pan.velocity(in: view)
            return abs(velocity.x) > abs(velocity.y) * 1.2 && abs(velocity.x) > 100
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handleHorizontalPan(_ gesture: UIPanGestureRecognizer) {
            guard let pdfView = gesture.view as? PDFView,
                  let document = pdfView.document else { return }
            if gesture.state == .began {
                parent.pageSource.clearPageProtection(in: document)
            }
            guard !parent.isContinuous else {
                swipeStartPage = nil
                return
            }

            switch gesture.state {
            case .began:
                swipeStartPage = PDFViewConfigurator.currentPageNumber(
                    in: pdfView,
                    fallback: parent.currentPage
                )
            case .ended:
                guard let startPage = swipeStartPage else { return }
                swipeStartPage = nil
                let translation = gesture.translation(in: pdfView)
                guard abs(translation.x) > 60,
                      abs(translation.x) > abs(translation.y) else { return }
                let isSwipingLeft = translation.x < 0

                // Let PDFKit's page controller finish first when its native curl gesture won.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self,
                          !self.isDismantled,
                          pdfView.document === document else { return }
                    let visiblePage = PDFViewConfigurator.currentPageNumber(
                        in: pdfView,
                        fallback: self.parent.currentPage
                    )
                    guard visiblePage == startPage else {
                        self.parent.currentPage = visiblePage
                        self.parent.pageInputText = "\(visiblePage)"
                        self.appliedPage = visiblePage
                        return
                    }
                    guard self.parent.currentPage == startPage else { return }

                    let forward = isSwipingLeft != self.parent.readingMode.isRTL
                    if forward { self.parent.onNext() }
                    else { self.parent.onPrevious() }
                }
            case .cancelled, .failed:
                swipeStartPage = nil
            default:
                break
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
