import SwiftUI
import PDFKit

// MARK: - PDF Document Reordering Logic
extension PDFDocument {
    /// Creates a new PDFDocument with pages reordered for a simulated RTL book view.
    /// The new order will be [1, 3, 2, 5, 4, ...]. When displayed in a standard LTR book view,
    /// this creates the visual effect of an RTL layout.
    func reorderedForRTL() -> PDFDocument {
        let newDocument = PDFDocument()
        let originalPageCount = self.pageCount

        guard originalPageCount > 0 else {
            return newDocument
        }

        // The first page (cover) is always displayed alone on the right.
        if let firstPage = self.page(at: 0)?.copy() as? PDFPage {
            newDocument.insert(firstPage, at: 0)
        }

        // Process the rest of the pages in swapped pairs.
        var i = 1
        while i < originalPageCount {
            if i + 1 < originalPageCount {
                // This is a pair of pages, e.g., pages 2 and 3 (at indices 1 and 2).
                // We get them and insert them in reverse order.
                if let rightPage = self.page(at: i + 1)?.copy() as? PDFPage,
                   let leftPage = self.page(at: i)?.copy() as? PDFPage {
                    newDocument.insert(rightPage, at: newDocument.pageCount)
                    newDocument.insert(leftPage, at: newDocument.pageCount)
                }
            } else {
                // This is the last, unpaired page.
                if let lastPage = self.page(at: i)?.copy() as? PDFPage {
                    newDocument.insert(lastPage, at: newDocument.pageCount)
                }
            }
            i += 2
        }
        return newDocument
    }
}


// MARK: - Reading Mode Enum (Common)
enum ReadingMode: String, CaseIterable, Identifiable {
    case singlePage = "單頁"
    case twoPagesLTR = "雙頁 (左至右)"
    case twoPagesRTL = "雙頁 (書本模式)"
    var id: String { self.rawValue }
}

// MARK: - Zoom Level Enum
enum ZoomLevel: String, CaseIterable, Identifiable {
    case fitPage = "適應頁面"
    case fitWidth = "適應寬度"
    case percent50 = "50%"
    case percent75 = "75%"
    case percent100 = "100%"
    case percent125 = "125%"
    case percent150 = "150%"
    case percent200 = "200%"
    
    var id: String { self.rawValue }
    
    var scaleFactor: CGFloat? {
        switch self {
        case .fitPage, .fitWidth: return nil
        case .percent50: return 0.5
        case .percent75: return 0.75
        case .percent100: return 1.0
        case .percent125: return 1.25
        case .percent150: return 1.5
        case .percent200: return 2.0
        }
    }
}

// MARK: - PDF Error Handling
enum PDFError: LocalizedError {
    case fileNotFound
    case invalidPDF
    case cannotRead
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "找不到 PDF 檔案"
        case .invalidPDF: return "無效的 PDF 檔案或檔案已損壞"
        case .cannotRead: return "無法讀取 PDF 檔案，請檢查檔案權限"
        }
    }
}

// MARK: - PDF View (Platform-Agnostic Wrapper)
struct PDFKitView: View {
    let document: PDFDocument
    @Binding var readingMode: ReadingMode
    @Binding var currentPage: Int
    @Binding var pageInputText: String
    @Binding var zoomLevel: ZoomLevel

    var body: some View {
#if os(macOS)
        macOS_PDFKitView(document: document, readingMode: $readingMode, currentPage: $currentPage, pageInputText: $pageInputText, zoomLevel: $zoomLevel)
#elseif os(iOS)
        iOS_PDFKitView(document: document, readingMode: $readingMode, currentPage: $currentPage, pageInputText: $pageInputText, zoomLevel: $zoomLevel)
#endif
    }
}

// MARK: - Main ContentView
struct ContentView: View {
    @State private var originalDocument: PDFDocument?
    @State private var displayedDocument: PDFDocument?
    
    @State private var readingMode: ReadingMode = .singlePage
    @State private var isFilePickerPresented = false
    @State private var isToolbarHidden = false
    
    // Page navigation
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 0
    @State private var pageInputText: String = ""
    
    // Zoom control
    @State private var currentZoom: ZoomLevel = .fitPage
    @State private var customZoomFactor: CGFloat = 1.0
    
    // Error handling
    @State private var errorMessage: String?
    @State private var showError = false

    private var mainContent: some View {
        VStack(spacing: 0) {
            if let document = displayedDocument {
                PDFKitView(document: document, readingMode: $readingMode, currentPage: $currentPage, pageInputText: $pageInputText, zoomLevel: $currentZoom)
                    .onTapGesture {
#if os(iOS)
                        withAnimation { isToolbarHidden.toggle() }
#endif
                    }
            } else {
                VStack {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 60)).padding(.bottom)
                    Text("請開啟一個 PDF 檔案").font(.title)
                }.foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var toolbarItems: some View {
        // Page navigation controls
        if originalDocument != nil {
            Button(action: goToPreviousPage) {
                Image(systemName: "chevron.left")
            }
            .disabled(currentPage <= 1)
            .help("上一頁")
            
            TextField("頁碼", text: $pageInputText)
                .frame(width: 40)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .onSubmit {
                    if let pageNum = Int(pageInputText), pageNum != 0 {
                        goToPage(pageNum)
                    }
                }
            
            Text("/")
            Text("\(totalPages)")
                .frame(minWidth: 30)
            
            Button(action: goToNextPage) {
                Image(systemName: "chevron.right")
            }
            .disabled(currentPage >= totalPages)
            .help("下一頁")
            
            Divider()
            
            // Zoom controls
            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("縮小")
            
            Picker("縮放", selection: $currentZoom) {
                ForEach(ZoomLevel.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)
            .help("縮放比例")
            
            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("放大")
            
            Divider()
            
            // Reading mode controls
            Picker("閱讀模式", selection: $readingMode) {
                ForEach(ReadingMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            .help("切換閱讀模式")
            Divider()
        }

        Button("開啟檔案") {
            openFile()
        }.help("選擇要開啟的 PDF 檔案")
    }

    var body: some View {
        Group {
#if os(macOS)
            mainContent
                .frame(minWidth: 400, minHeight: 300)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in isToolbarHidden = true }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in isToolbarHidden = false }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) { toolbarItems }
                }
                .toolbar(isToolbarHidden ? .hidden : .automatic, for: .windowToolbar)
                .focusedSceneValue(\.isInApp, true)
                .onKeyPress(.space) {
                    goToNextPage()
                    return .handled
                }
                .onKeyPress(.pageDown) {
                    goToNextPage()
                    return .handled
                }
                .onKeyPress(.pageUp) {
                    goToPreviousPage()
                    return .handled
                }
                .onKeyPress(.home) {
                    goToPage(1)
                    return .handled
                }
                .onKeyPress(.end) {
                    goToPage(totalPages)
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    goToPreviousPage()
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    goToNextPage()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    goToPreviousPage()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    goToNextPage()
                    return .handled
                }
#elseif os(iOS)
            NavigationView {
                mainContent
                    .navigationBarTitleDisplayMode(.inline)
                    .sheet(isPresented: $isFilePickerPresented) {
                        DocumentPicker { url in
                            loadPDF(from: url)
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) { toolbarItems }
                    }
                    .toolbar(isToolbarHidden ? .hidden : .automatic, for: .navigationBar)
            }
            .navigationViewStyle(.stack)
#endif
        }
        .alert("錯誤", isPresented: $showError) {
            Button("確定", role: .cancel) { }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .onChange(of: originalDocument) {
            updateDisplayedDocument()
        }
        .onChange(of: readingMode) {
            updateDisplayedDocument()
        }
        // Keyboard shortcuts (macOS)
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("開啟檔案...") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            
            CommandMenu("縮放") {
                Button("放大") {
                    zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(originalDocument == nil)
                
                Button("縮小") {
                    zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(originalDocument == nil)
                
                Button("實際大小") {
                    currentZoom = .percent100
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(originalDocument == nil)
                
                Divider()
                
                Button("適應頁面") {
                    currentZoom = .fitPage
                }
                .disabled(originalDocument == nil)
                
                Button("適應寬度") {
                    currentZoom = .fitWidth
                }
                .disabled(originalDocument == nil)
            }
        }
        #endif
    }
    
    private func updateDisplayedDocument() {
        guard let doc = originalDocument else {
            displayedDocument = nil
            totalPages = 0
            currentPage = 1
            pageInputText = ""
            return
        }

        #if os(iOS)
        if readingMode == .twoPagesRTL {
            // On iOS, we create a reordered document for RTL book mode.
            displayedDocument = doc.reorderedForRTL()
        } else {
            displayedDocument = doc
        }
        #else
        // On macOS, PDFKit handles RTL natively, so we always use the original document.
        displayedDocument = doc
        #endif
        
        // Update page info
        totalPages = doc.pageCount
        currentPage = 1
        pageInputText = "1"
    }
    
    // MARK: - Page Navigation Methods
    private func goToPage(_ pageNumber: Int) {
        guard pageNumber >= 1 && pageNumber <= totalPages else { return }
        currentPage = pageNumber
        pageInputText = "\(pageNumber)"
        // The actual page change will be handled by the PDFView through binding
    }
    
    private func goToPreviousPage() {
        if currentPage > 1 {
            goToPage(currentPage - 1)
        }
    }
    
    private func goToNextPage() {
        if currentPage < totalPages {
            goToPage(currentPage + 1)
        }
    }
    
    // MARK: - Zoom Methods
    private func zoomIn() {
        let zoomLevels = ZoomLevel.allCases.filter { $0.scaleFactor != nil }
        if let currentIndex = zoomLevels.firstIndex(of: currentZoom),
           currentIndex < zoomLevels.count - 1 {
            currentZoom = zoomLevels[currentIndex + 1]
        }
    }
    
    private func zoomOut() {
        let zoomLevels = ZoomLevel.allCases.filter { $0.scaleFactor != nil }
        if let currentIndex = zoomLevels.firstIndex(of: currentZoom),
           currentIndex > 0 {
            currentZoom = zoomLevels[currentIndex - 1]
        }
    }
    
    // MARK: - File Opening with Error Handling
    private func openFile() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url {
            loadPDF(from: url)
        }
#elseif os(iOS)
        isFilePickerPresented = true
#endif
    }
    
    private func loadPDF(from url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = PDFError.fileNotFound.errorDescription
            showError = true
            return
        }
        
        guard let document = PDFDocument(url: url) else {
            errorMessage = PDFError.invalidPDF.errorDescription
            showError = true
            return
        }
        
        guard document.pageCount > 0 else {
            errorMessage = PDFError.invalidPDF.errorDescription
            showError = true
            return
        }
        
        self.originalDocument = document
    }
}

// MARK: - macOS Specific Implementation
#if os(macOS)
struct macOS_PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var readingMode: ReadingMode
    @Binding var currentPage: Int
    @Binding var pageInputText: String
    @Binding var zoomLevel: ZoomLevel
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.pageBreakMargins = .zero
        
        // Add page changed notification observer
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        // Add pan gesture for swipe navigation
        let panGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pdfView.addGestureRecognizer(panGesture)
        
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.parent = self
        
        // Update document if changed
        if nsView.document != document {
            nsView.document = document
            nsView.goToFirstPage(nil)
        }
        
        // Update reading mode
        nsView.pageBreakMargins = .zero
        
        switch readingMode {
        case .singlePage:
            nsView.displayMode = .singlePage
            nsView.displaysAsBook = false
            nsView.displaysRTL = false
        case .twoPagesLTR:
            nsView.displayMode = .twoUp
            nsView.displaysAsBook = true
            nsView.displaysRTL = false
        case .twoPagesRTL:
            nsView.displayMode = .twoUp
            nsView.displaysAsBook = true
            nsView.displaysRTL = true
        }
        
        // Update zoom level
        applyZoom(to: nsView, level: zoomLevel)
        
        // Update current page if it changed externally
        if currentPage >= 1, currentPage <= (nsView.document?.pageCount ?? 0),
           let targetPage = nsView.document?.page(at: currentPage - 1),
           nsView.currentPage != targetPage {
            nsView.go(to: targetPage)
        }
    }
    
    private func applyZoom(to pdfView: PDFView, level: ZoomLevel) {
        switch level {
        case .fitPage:
            pdfView.autoScales = true
        case .fitWidth:
            pdfView.autoScales = false
            if let page = pdfView.currentPage {
                let pageBounds = page.bounds(for: .mediaBox)
                let viewWidth = pdfView.bounds.width
                let scale = viewWidth / pageBounds.width
                pdfView.scaleFactor = scale
            }
        default:
            pdfView.autoScales = false
            if let scaleFactor = level.scaleFactor {
                pdfView.scaleFactor = scaleFactor
            }
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    
    class Coordinator: NSObject {
        var parent: macOS_PDFKitView
        private var startPoint: NSPoint?

        init(parent: macOS_PDFKitView) {
            self.parent = parent
        }
        
        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPDFPage = pdfView.currentPage,
                  let document = pdfView.document else {
                return
            }
            let pageIndex = document.index(for: currentPDFPage)
            
            // Update the binding and text field
            DispatchQueue.main.async {
                self.parent.currentPage = pageIndex + 1
                self.parent.pageInputText = "\(pageIndex + 1)"
            }
        }

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let view = gesture.view as? PDFView else { return }
            switch gesture.state {
            case .began:
                startPoint = gesture.location(in: view)
            case .ended:
                guard let start = startPoint else { return }
                let end = gesture.location(in: view)
                let translation = NSPoint(x: end.x - start.x, y: end.y - start.y)

                if abs(translation.x) > abs(translation.y) && abs(translation.x) > 50 {
                    let isBookMode = parent.readingMode == .twoPagesRTL
                    
                    if translation.x < 0 { // Swipe Left
                        if isBookMode {
                            if view.canGoToPreviousPage { view.goToPreviousPage(nil) }
                        } else {
                            if view.canGoToNextPage { view.goToNextPage(nil) }
                        }
                    } else { // Swipe Right
                        if isBookMode {
                            if view.canGoToNextPage { view.goToNextPage(nil) }
                        } else {
                            if view.canGoToPreviousPage { view.goToPreviousPage(nil) }
                        }
                    }
                }
                startPoint = nil
            default: break
            }
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
#endif

// MARK: - iOS Specific Implementation
#if os(iOS)
struct iOS_PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var readingMode: ReadingMode
    @Binding var currentPage: Int
    @Binding var pageInputText: String
    @Binding var zoomLevel: ZoomLevel

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        
        // Add page changed notification observer
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeLeft.direction = .left
        pdfView.addGestureRecognizer(swipeLeft)
        
        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeRight.direction = .right
        pdfView.addGestureRecognizer(swipeRight)
        
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        context.coordinator.parent = self
        if uiView.document != document {
            uiView.document = document
            uiView.goToFirstPage(nil)
        }
        
        uiView.pageBreakMargins = .zero
        
        switch readingMode {
        case .singlePage:
            uiView.displayMode = .singlePage
            uiView.displaysAsBook = false
        case .twoPagesLTR, .twoPagesRTL:
            uiView.displayMode = .twoUp
            uiView.displaysAsBook = true
        }
        
        // Update zoom level
        applyZoom(to: uiView, level: zoomLevel)
        
        // Update current page if it changed externally
        if currentPage >= 1, currentPage <= (uiView.document?.pageCount ?? 0),
           let targetPage = uiView.document?.page(at: currentPage - 1),
           uiView.currentPage != targetPage {
            uiView.go(to: targetPage)
        }
    }
    
    private func applyZoom(to pdfView: PDFView, level: ZoomLevel) {
        switch level {
        case .fitPage:
            pdfView.autoScales = true
        case .fitWidth:
            pdfView.autoScales = false
            if let page = pdfView.currentPage {
                let pageBounds = page.bounds(for: .mediaBox)
                let viewWidth = pdfView.bounds.width
                let scale = viewWidth / pageBounds.width
                pdfView.scaleFactor = scale
            }
        default:
            pdfView.autoScales = false
            if let scaleFactor = level.scaleFactor {
                pdfView.scaleFactor = scaleFactor
            }
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    
    class Coordinator: NSObject {
        var parent: iOS_PDFKitView

        init(parent: iOS_PDFKitView) {
            self.parent = parent
        }
        
        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPDFPage = pdfView.currentPage,
                  let document = pdfView.document else {
                return
            }
            let pageIndex = document.index(for: currentPDFPage)
            
            // Update the binding and text field
            DispatchQueue.main.async {
                self.parent.currentPage = pageIndex + 1
                self.parent.pageInputText = "\(pageIndex + 1)"
            }
        }

        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            guard let view = gesture.view as? PDFView else { return }
            
            let isBookMode = parent.readingMode == .twoPagesRTL

            if gesture.direction == .left {
                if isBookMode {
                    if view.canGoToPreviousPage { view.goToPreviousPage(nil) }
                } else {
                    if view.canGoToNextPage { view.goToNextPage(nil) }
                }
            } else if gesture.direction == .right {
                if isBookMode {
                    if view.canGoToNextPage { view.goToNextPage(nil) }
                } else {
                    if view.canGoToPreviousPage { view.goToPreviousPage(nil) }
                }
            }
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
    }
}
#endif

#Preview {
    ContentView()
}

