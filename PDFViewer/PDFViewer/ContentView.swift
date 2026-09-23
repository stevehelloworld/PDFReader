import SwiftUI
import PDFKit
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    #if os(macOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    #endif
    // Document session
    @State private var document: PDFDocument?
    @State private var currentFileURL: URL?
    @State private var currentFileName: String?
    @State private var currentFileID: String?
    @State private var currentBookmark: Data?

    // Reader state
    @State private var readingMode: ReadingMode = .singlePage
    @State private var isContinuous = false
    @State private var currentPage = 1
    @State private var totalPages = 0
    @State private var pageInputText = ""
    @State private var currentZoom: ZoomLevel = .fitPage
    @State private var appearance: ReadingAppearance = .automatic

    // Chrome
    @State private var isToolbarHidden = false
    @State private var showSidebar = false
    @State private var sidebarTab: SidebarTab = .thumbnails
    @State private var showSearch = false
    @State private var showScrubber = true
    @State private var isFilePickerPresented = false

    // Search
    @State private var searchQuery = ""
    @State private var searchResults: [PDFSelection] = []
    @State private var selectedResultIndex = 0
    @State private var isSearching = false
    @State private var searchProgress = 0
    @State private var searchPageCount = 0
    @State private var pendingSelection: PDFSelection?

    // Loading / errors
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false

    // Progress debounce
    @State private var saveTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var activeLoadRequest: UUID?

    @ObservedObject private var historyManager = PDFHistoryManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            #if os(macOS)
            macOSRoot
            #else
            iOSRoot
            #endif
        }
        .alert(String(localized: "錯誤"), isPresented: $showError) {
            Button(String(localized: "確定"), role: .cancel) {}
            if document == nil {
                Button(String(localized: "開啟檔案")) { openFile() }
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .onChange(of: currentPage) { oldPage, newPage in
            guard oldPage != newPage else { return }
            pageInputText = "\(newPage)"
            scheduleSaveProgress()
        }
        .onChange(of: readingMode) { _, _ in scheduleSaveProgress() }
        .onChange(of: isContinuous) { _, _ in scheduleSaveProgress() }
        .onChange(of: appearance) { _, _ in scheduleSaveProgress() }
        .onChange(of: currentZoom) { _, _ in scheduleSaveProgress() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                saveTask?.cancel()
                saveCurrentProgress()
            }
        }
        .onDisappear {
            saveTask?.cancel()
            cancelSearch()
            activeLoadRequest = nil
            saveCurrentProgress()
            if let currentFileURL {
                SecurityScopedURLResolver.stopAccess(currentFileURL)
            }
        }
        .modifier(OpenURLModifier { url in
            Task { await loadPDF(from: url) }
        })
        #if os(macOS)
        .focusedSceneValue(\.readerCommands, ReaderCommands(
            openFile: openFile,
            previousPage: goToPreviousPage,
            nextPage: goToNextPage,
            toggleSidebar: { withAnimation { showSidebar.toggle() } },
            toggleSearch: { withAnimation { showSearch.toggle() } },
            toggleContinuous: { isContinuous.toggle() },
            zoomIn: zoomIn,
            zoomOut: zoomOut,
            zoomActualSize: { currentZoom = .percent100 },
            zoomFitPage: { currentZoom = .fitPage },
            zoomFitWidth: { currentZoom = .fitWidth },
            hasDocument: document != nil
        ))
        #endif
    }

    // MARK: - macOS layout

    #if os(macOS)
    private var macOSRoot: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            if let document {
                DocumentSidebarView(
                    document: document,
                    currentPage: $currentPage,
                    selectedTab: $sidebarTab,
                    onSelectPage: goToPage
                )
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
            } else {
                Color.clear.frame(width: 0)
            }
        } detail: {
            readerContainer
                .frame(minWidth: 480, minHeight: 360)
                .navigationTitle(currentFileName ?? "ComicPDFReader")
                .toolbar { macToolbar }
                .toolbar(isToolbarHidden ? .hidden : .automatic, for: .windowToolbar)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
                    isToolbarHidden = true
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
                    isToolbarHidden = false
                }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: showSidebar) { _, visible in
            withAnimation {
                columnVisibility = visible && document != nil ? .all : .detailOnly
            }
        }
        .onChange(of: document != nil) { _, hasDoc in
            if !hasDoc {
                showSidebar = false
                columnVisibility = .detailOnly
            }
        }
        .sheet(isPresented: $showSearch) {
            if let document {
                searchSheet(document: document)
                    .frame(minWidth: 360, minHeight: 420)
            }
        }
    }

    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if document != nil {
                Button {
                    withAnimation { showSidebar.toggle() }
                } label: {
                    Label(String(localized: "側邊欄"), systemImage: "sidebar.left")
                }
                .help(String(localized: "縮圖與目錄"))

                pageNavigationControls
            }
        }

        ToolbarItemGroup(placement: .principal) {
            if document != nil {
                readingModePicker
                continuousToggle
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if document != nil {
                Button {
                    showSearch = true
                } label: {
                    Label(String(localized: "搜尋"), systemImage: "magnifyingglass")
                }
                .help(String(localized: "搜尋 PDF"))

                appearanceMenu
                zoomControls

                Button(action: openFile) {
                    Label(String(localized: "開啟"), systemImage: "doc.badge.plus")
                }
                .help(String(localized: "選擇要開啟的 PDF 檔案"))
            } else {
                Button(action: openFile) {
                    Label(String(localized: "開啟檔案"), systemImage: "doc.badge.plus")
                }
            }
        }
    }
    #endif

    // MARK: - iOS layout

    #if os(iOS)
    private var iOSRoot: some View {
        NavigationStack {
            readerContainer
                .navigationTitle(currentFileName ?? "ComicPDFReader")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { iOSToolbar }
                .toolbar(isToolbarHidden ? .hidden : .automatic, for: .navigationBar)
                .toolbar(isToolbarHidden ? .hidden : .automatic, for: .bottomBar)
                .safeAreaInset(edge: .bottom) {
                    if document != nil, !isToolbarHidden, horizontalSizeClass == .compact {
                        iPhoneBottomBar
                    }
                }
        }
        .sheet(isPresented: $isFilePickerPresented) {
            DocumentPicker { url in
                Task { await loadPDF(from: url) }
            }
        }
        .sheet(isPresented: $showSearch) {
            if let document {
                NavigationStack {
                    searchSheet(document: document)
                        .navigationTitle(String(localized: "搜尋"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(String(localized: "完成")) { showSearch = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showSidebar) {
            if let document {
                NavigationStack {
                    DocumentSidebarView(
                        document: document,
                        currentPage: $currentPage,
                        selectedTab: $sidebarTab,
                        onSelectPage: { page in
                            goToPage(page)
                            showSidebar = false
                        }
                    )
                    .navigationTitle(String(localized: "瀏覽"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "完成")) { showSidebar = false }
                        }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var iOSToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if document != nil {
                Button {
                    showSidebar = true
                } label: {
                    Label(String(localized: "側邊欄"), systemImage: "sidebar.left")
                }
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if document != nil {
                if horizontalSizeClass != .compact {
                    pageNavigationControls
                    readingModePicker
                }
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                }
                Menu {
                    readingModeMenuContent
                    Toggle(String(localized: "連續捲動"), isOn: $isContinuous)
                    Divider()
                    appearanceMenuContent
                    Divider()
                    zoomMenuContent
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            Button(action: openFile) {
                Image(systemName: "doc.badge.plus")
            }
            .accessibilityLabel(String(localized: "開啟檔案"))
        }
    }

    private var iPhoneBottomBar: some View {
        HStack(spacing: 16) {
            Button(action: goToPreviousPage) {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .disabled(currentPage <= 1)
            .accessibilityLabel(String(localized: "上一頁"))

            HStack(spacing: 4) {
                TextField(String(localized: "頁碼"), text: $pageInputText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 48)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitPageInput() }

                Text("/ \(totalPages)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button(action: goToNextPage) {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(currentPage >= totalPages)
            .accessibilityLabel(String(localized: "下一頁"))

            Spacer(minLength: 0)

            Picker("", selection: $readingMode) {
                ForEach(ReadingMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon)
                        .labelStyle(.iconOnly)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
            .accessibilityLabel(String(localized: "閱讀模式"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
    #endif

    // MARK: - Shared reader container

    private var readerContainer: some View {
        ZStack {
            if let document {
                readerStack(document: document)
            } else {
                EmptyStateView(
                    historyManager: historyManager,
                    isLoading: isLoading,
                    onOpen: openFile,
                    onOpenRecent: { file in Task { await openRecent(file) } },
                    onRemoveRecent: { historyManager.removeFile(id: $0.id) },
                    onClearRecents: { historyManager.clearAll() }
                )
            }

            if isLoading, document != nil {
                LoadingOverlay(message: String(localized: "正在載入…"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .onDrop(of: [UTType.fileURL, UTType.pdf], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        #endif
        .focusable()
        .onKeyPress(.leftArrow) {
            goToPreviousPage()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            goToNextPage()
            return .handled
        }
        .onKeyPress(.space) {
            goToNextPage()
            return .handled
        }
        .onKeyPress(.escape) {
            if showSearch { showSearch = false; return .handled }
            if showSidebar { showSidebar = false; return .handled }
            return .ignored
        }
    }

    private func readerStack(document: PDFDocument) -> some View {
        VStack(spacing: 0) {
            ZStack {
                PDFKitView(
                    document: document,
                    readingMode: $readingMode,
                    isContinuous: $isContinuous,
                    currentPage: $currentPage,
                    pageInputText: $pageInputText,
                    zoomLevel: $currentZoom,
                    appearance: $appearance,
                    pendingSelection: pendingSelection,
                    onSelectionConsumed: { pendingSelection = nil },
                    onPrevious: goToPreviousPage,
                    onNext: goToNextPage
                )
                .compositingGroup()
                .overlay { AppearanceFilterOverlay(appearance: appearance) }

                if !isContinuous {
                    EdgeTapOverlay(
                        isRTL: readingMode.isRTL,
                        onPrevious: goToPreviousPage,
                        onNext: goToNextPage
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                withAnimation {
                    isToolbarHidden.toggle()
                    showScrubber.toggle()
                }
            }

            if showScrubber, !isToolbarHidden {
                PageScrubber(currentPage: $currentPage, totalPages: totalPages, onSeek: goToPage)
            }
        }
    }

    private func searchSheet(document: PDFDocument) -> some View {
        SearchPanel(
            document: document,
            query: $searchQuery,
            results: $searchResults,
            selectedResultIndex: $selectedResultIndex,
            isSearching: isSearching,
            searchProgress: searchProgress,
            searchPageCount: searchPageCount,
            onSelect: { selection in
                pendingSelection = selection
                if let page = selection.pages.first {
                    goToPage(document.index(for: page) + 1)
                }
            },
            onQueryChanged: searchQueryDidChange,
            onSearch: { performSearch(in: document) }
        )
    }

    // MARK: - Toolbar building blocks

    private var pageNavigationControls: some View {
        HStack(spacing: 6) {
            Button(action: goToPreviousPage) {
                Image(systemName: "chevron.left")
            }
            .disabled(currentPage <= 1)
            .help(String(localized: "上一頁"))
            .accessibilityLabel(String(localized: "上一頁"))

            HStack(spacing: 4) {
                TextField(String(localized: "頁碼"), text: $pageInputText)
                    .frame(width: 44)
                    .multilineTextAlignment(.center)
                    #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                    #endif
                    .onSubmit { submitPageInput() }

                Text("/")
                    .foregroundStyle(.secondary)
                Text("\(totalPages)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button(action: goToNextPage) {
                Image(systemName: "chevron.right")
            }
            .disabled(currentPage >= totalPages)
            .help(String(localized: "下一頁"))
            .accessibilityLabel(String(localized: "下一頁"))
        }
    }

    private var readingModePicker: some View {
        Picker(String(localized: "閱讀模式"), selection: $readingMode) {
            ForEach(ReadingMode.allCases) { mode in
                Label(mode.label, systemImage: mode.icon).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
        .help(String(localized: "閱讀模式"))
    }

    private var continuousToggle: some View {
        Toggle(isOn: $isContinuous) {
            Image(systemName: "rectangle.stack")
        }
        .toggleStyle(.button)
        .help(String(localized: "連續捲動"))
        .accessibilityLabel(String(localized: "連續捲動"))
    }

    private var appearanceMenu: some View {
        Menu {
            appearanceMenuContent
        } label: {
            Label(appearance.label, systemImage: appearance.icon)
        }
        .help(String(localized: "外觀"))
    }

    @ViewBuilder
    private var appearanceMenuContent: some View {
        ForEach(ReadingAppearance.allCases) { mode in
            Button {
                appearance = mode
            } label: {
                Label(mode.label, systemImage: mode.icon)
            }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .help(String(localized: "縮小"))
            .accessibilityLabel(String(localized: "縮小"))

            Picker(String(localized: "縮放"), selection: $currentZoom) {
                ForEach(ZoomLevel.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .frame(width: 96)
            .help(String(localized: "縮放比例"))

            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .help(String(localized: "放大"))
            .accessibilityLabel(String(localized: "放大"))
        }
    }

    @ViewBuilder
    private var readingModeMenuContent: some View {
        ForEach(ReadingMode.allCases) { mode in
            Button {
                readingMode = mode
            } label: {
                Label(mode.label, systemImage: mode.icon)
            }
        }
    }

    @ViewBuilder
    private var zoomMenuContent: some View {
        ForEach(ZoomLevel.allCases) { level in
            Button(level.displayName) { currentZoom = level }
        }
    }

    // MARK: - Navigation

    private func goToPage(_ pageNumber: Int) {
        guard pageNumber >= 1, pageNumber <= totalPages else { return }
        currentPage = pageNumber
        pageInputText = "\(pageNumber)"
    }

    private func goToPreviousPage() {
        if currentPage > 1 { goToPage(currentPage - 1) }
    }

    private func goToNextPage() {
        if currentPage < totalPages { goToPage(currentPage + 1) }
    }

    private func submitPageInput() {
        if let pageNum = Int(pageInputText), (1...totalPages).contains(pageNum) {
            goToPage(pageNum)
        } else {
            pageInputText = "\(currentPage)"
        }
    }

    // MARK: - Zoom

    private func zoomIn() {
        let levels = ZoomLevel.percentageLevels
        if currentZoom == .fitPage || currentZoom == .fitWidth {
            currentZoom = .percent100
            return
        }
        if let idx = levels.firstIndex(of: currentZoom), idx < levels.count - 1 {
            currentZoom = levels[idx + 1]
        }
    }

    private func zoomOut() {
        let levels = ZoomLevel.percentageLevels
        if currentZoom == .fitPage || currentZoom == .fitWidth {
            currentZoom = .percent100
            return
        }
        if let idx = levels.firstIndex(of: currentZoom), idx > 0 {
            currentZoom = levels[idx - 1]
        }
    }

    // MARK: - Search

    private func performSearch(in document: PDFDocument) {
        cancelSearch()
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchResults = []
            return
        }

        searchResults = []
        selectedResultIndex = 0
        searchProgress = 0
        searchPageCount = document.pageCount
        isSearching = true

        // Keep PDFKit on the main actor, but search one page at a time and yield between
        // pages so large documents don't monopolize the UI for one full-document call.
        searchTask = Task { @MainActor in
            var selections: [PDFSelection] = []
            let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

            for pageIndex in 0..<document.pageCount {
                guard !Task.isCancelled,
                      self.document === document,
                      self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == q
                else { return }

                if let page = document.page(at: pageIndex), let pageString = page.string {
                    let pageText = pageString as NSString
                    var cursor = 0

                    while cursor < pageText.length {
                        let remainingRange = NSRange(location: cursor, length: pageText.length - cursor)
                        let match = pageText.range(of: q, options: options, range: remainingRange)
                        guard match.location != NSNotFound else { break }
                        if let selection = page.selection(for: match) {
                            selections.append(selection)
                        }
                        cursor = NSMaxRange(match)
                    }
                }

                if (pageIndex + 1).isMultiple(of: 8) || pageIndex + 1 == document.pageCount {
                    searchProgress = pageIndex + 1
                }
                await Task.yield()
            }

            guard !Task.isCancelled,
                  self.document === document,
                  searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == q
            else { return }
            searchResults = selections
            selectedResultIndex = 0
            isSearching = false
            if let first = selections.first {
                pendingSelection = first
                if let page = first.pages.first {
                    goToPage(document.index(for: page) + 1)
                }
            }
            searchTask = nil
        }
    }

    private func searchQueryDidChange() {
        cancelSearch()
        searchResults = []
        selectedResultIndex = 0
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        searchProgress = 0
        searchPageCount = 0
    }

    // MARK: - File open / load

    private func openFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await loadPDF(from: url) }
        }
        #elseif os(iOS)
        isFilePickerPresented = true
        #endif
    }

    private func openRecent(_ file: RecentFile) async {
        let requestID = UUID()
        activeLoadRequest = requestID
        isLoading = true
        defer {
            if activeLoadRequest == requestID {
                isLoading = false
                activeLoadRequest = nil
            }
        }
        do {
            let loaded = try await PDFDocumentLoader.load(recent: file)
            guard activeLoadRequest == requestID else {
                SecurityScopedURLResolver.stopAccess(loaded.url)
                return
            }
            replaceCurrentDocument(with: loaded, restoring: file)
        } catch {
            guard activeLoadRequest == requestID else { return }
            presentError(error)
            if let pdfError = error as? PDFError, case .fileNotFound = pdfError {
                historyManager.removeFile(id: file.id)
            }
        }
    }

    private func loadPDF(from url: URL, existingBookmark: Data? = nil) async {
        let requestID = UUID()
        activeLoadRequest = requestID
        isLoading = true
        defer {
            if activeLoadRequest == requestID {
                isLoading = false
                activeLoadRequest = nil
            }
        }

        do {
            let loaded = try await PDFDocumentLoader.load(from: url, existingBookmark: existingBookmark)
            guard activeLoadRequest == requestID else {
                SecurityScopedURLResolver.stopAccess(loaded.url)
                return
            }
            let saved = historyManager.getProgress(id: loaded.fileID, matching: loaded.url)
            replaceCurrentDocument(with: loaded, restoring: saved)
        } catch {
            guard activeLoadRequest == requestID else { return }
            presentError(error)
        }
    }

    private func replaceCurrentDocument(with loaded: LoadedPDF, restoring progress: RecentFile?) {
        cancelSearch()
        searchResults = []
        pendingSelection = nil
        saveTask?.cancel()
        saveCurrentProgress()

        let previousURL = currentFileURL
        applyLoaded(loaded, restoring: progress)
        if let previousURL {
            SecurityScopedURLResolver.stopAccess(previousURL)
        }
    }

    private func applyLoaded(_ loaded: LoadedPDF, restoring progress: RecentFile?) {
        document = loaded.document
        currentFileURL = loaded.url
        currentFileName = loaded.fileName
        currentFileID = loaded.fileID
        currentBookmark = loaded.bookmarkData
        totalPages = loaded.document.pageCount

        if let progress {
            if let mode = ReadingMode(rawValue: progress.readingMode) {
                readingMode = mode
            }
            isContinuous = progress.isContinuous
            if let app = ReadingAppearance(rawValue: progress.appearance) {
                appearance = app
            }
            currentZoom = ZoomLevel(rawValue: progress.zoomLevel) ?? .fitPage
            let page = min(max(progress.currentPage, 1), totalPages)
            currentPage = page
            pageInputText = "\(page)"
        } else {
            readingMode = .singlePage
            isContinuous = false
            appearance = .automatic
            currentZoom = .fitPage
            currentPage = 1
            pageInputText = "1"
        }

        let entry = RecentFile(
            path: loaded.url.path,
            name: loaded.fileName,
            currentPage: currentPage,
            totalPages: totalPages,
            readingMode: readingMode,
            isContinuous: isContinuous,
            appearance: appearance,
            zoomLevel: currentZoom,
            bookmarkData: loaded.bookmarkData,
            id: loaded.fileID
        )
        historyManager.addRecentFile(entry)

        isToolbarHidden = false
        showScrubber = true
    }

    private func presentError(_ error: Error) {
        if let pdfError = error as? PDFError {
            errorMessage = pdfError.errorDescription
        } else {
            errorMessage = error.localizedDescription
        }
        showError = true
    }

    // MARK: - Progress

    private func scheduleSaveProgress() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            saveCurrentProgress()
        }
    }

    private func saveCurrentProgress() {
        guard let id = currentFileID else { return }
        historyManager.updateProgress(
            id: id,
            currentPage: currentPage,
            totalPages: totalPages,
            readingMode: readingMode,
            isContinuous: isContinuous,
            appearance: appearance,
            zoomLevel: currentZoom
        )
    }

    // MARK: - Drag & drop (macOS)

    #if os(macOS)
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL? = {
                    if let data = item as? Data {
                        return URL(dataRepresentation: data, relativeTo: nil)
                    }
                    if let url = item as? URL { return url }
                    if let str = item as? String { return URL(fileURLWithPath: str) }
                    return nil
                }()
                guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                Task { @MainActor in
                    await loadPDF(from: url)
                }
            }
            return true
        }
        return false
    }
    #endif
}

// MARK: - Open URL helper (cross-platform)

private struct OpenURLModifier: ViewModifier {
    let handler: (URL) -> Void

    func body(content: Content) -> some View {
        content.onOpenURL { url in
            handler(url)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
