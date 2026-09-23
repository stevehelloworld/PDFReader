import SwiftUI
import PDFKit

// MARK: - Sidebar (thumbnails + outline)

struct DocumentSidebarView: View {
    let document: PDFDocument
    @Binding var currentPage: Int
    @Binding var selectedTab: SidebarTab
    var onSelectPage: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider()

            switch selectedTab {
            case .thumbnails:
                ThumbnailListView(document: document, currentPage: currentPage, onSelectPage: onSelectPage)
            case .outline:
                OutlineListView(document: document, onSelectPage: onSelectPage)
            }
        }
        .frame(minWidth: 200)
    }
}

struct ThumbnailListView: View {
    let document: PDFDocument
    let currentPage: Int
    var onSelectPage: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        let pageNumber = index + 1
                        Button {
                            onSelectPage(pageNumber)
                        } label: {
                            VStack(spacing: 6) {
                                ThumbnailCell(document: document, pageIndex: index)
                                    .frame(height: 140)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(
                                                pageNumber == currentPage ? Color.accentColor : Color.primary.opacity(0.08),
                                                lineWidth: pageNumber == currentPage ? 2 : 1
                                            )
                                    )

                                Text("\(pageNumber)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(pageNumber == currentPage ? Color.accentColor : .secondary)
                            }
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        .id(pageNumber)
                        .accessibilityLabel(Text(String(localized: "第 \(pageNumber) 頁")))
                    }
                }
                .padding(.vertical, 12)
            }
            .onAppear {
                proxy.scrollTo(currentPage, anchor: .center)
            }
            .onChange(of: currentPage) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

struct ThumbnailCell: View {
    let document: PDFDocument
    let pageIndex: Int
    @State private var image: PlatformImage?

    private struct TaskKey: Hashable {
        let documentID: ObjectIdentifier
        let pageIndex: Int
    }

    var body: some View {
        Group {
            if let image {
                #if os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #else
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #endif
            } else {
                ProgressView()
            }
        }
        .task(id: TaskKey(documentID: ObjectIdentifier(document), pageIndex: pageIndex)) {
            image = nil
            let idx = pageIndex
            if let sourceURL = document.documentURL {
                let cache = PDFHistoryManager.shared
                let cacheKey = cache.pageThumbnailCacheKey(for: sourceURL, pageIndex: idx)
                if let cached = cache.cachedPageThumbnail(for: cacheKey) {
                    image = cached
                    return
                }

                let generated = await Task.detached(priority: .utility) {
                    autoreleasepool {
                        guard let isolatedDocument = PDFDocument(url: sourceURL),
                              let page = isolatedDocument.page(at: idx) else { return nil }
                        return page.thumbnail(of: CGSize(width: 160, height: 220), for: .mediaBox)
                    }
                }.value
                if let generated {
                    cache.storePageThumbnail(generated, for: cacheKey)
                    guard !Task.isCancelled else { return }
                    image = generated
                }
            } else if let page = document.page(at: idx) {
                let generated = page.thumbnail(of: CGSize(width: 160, height: 220), for: .mediaBox)
                image = generated
            }
        }
    }
}

struct OutlineListView: View {
    let document: PDFDocument
    var onSelectPage: (Int) -> Void

    private var entries: [OutlineEntry] {
        OutlineEntry.flatten(document.outlineRoot)
    }

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                String(localized: "沒有目錄"),
                systemImage: "list.bullet",
                description: Text(String(localized: "此 PDF 未提供大綱目錄。"))
            )
        } else {
            List(entries) { entry in
                Button {
                    if let page = entry.page, let document = page.document {
                        onSelectPage(document.index(for: page) + 1)
                    }
                } label: {
                    HStack {
                        Text(entry.title)
                            .lineLimit(2)
                            .padding(.leading, CGFloat(entry.depth) * 12)
                        Spacer()
                        if let page = entry.page, let document = page.document {
                            Text("\(document.index(for: page) + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.sidebar)
        }
    }
}

struct OutlineEntry: Identifiable {
    let id = UUID()
    let title: String
    let page: PDFPage?
    let depth: Int

    static func flatten(_ root: PDFOutline?, depth: Int = 0) -> [OutlineEntry] {
        guard let root else { return [] }
        var result: [OutlineEntry] = []
        let count = root.numberOfChildren
        guard count > 0 else { return result }

        for index in 0..<count {
            guard let node = root.child(at: index) else { continue }
            let title = (node.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                result.append(OutlineEntry(title: title, page: node.destination?.page, depth: depth))
            }
            result.append(contentsOf: flatten(node, depth: depth + 1))
        }
        return result
    }
}

// MARK: - Search

struct SearchPanel: View {
    let document: PDFDocument
    @Binding var query: String
    @Binding var results: [PDFSelection]
    @Binding var selectedResultIndex: Int
    let isSearching: Bool
    let searchProgress: Int
    let searchPageCount: Int
    var onSelect: (PDFSelection) -> Void
    var onQueryChanged: () -> Void
    var onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "搜尋 PDF…"), text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit(onSearch)
                    .onChange(of: query) { _, _ in onQueryChanged() }
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                        selectedResultIndex = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button(String(localized: "搜尋"), action: onSearch)
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(12)

            Divider()

            if isSearching {
                VStack(spacing: 12) {
                    ProgressView(
                        value: Double(searchProgress),
                        total: Double(max(searchPageCount, 1))
                    )
                    .frame(maxWidth: 260)
                    .accessibilityLabel(Text(String(localized: "搜尋中…")))

                    Text(String(localized: "搜尋中…"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else if results.isEmpty {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        String(localized: "搜尋文件"),
                        systemImage: "text.magnifyingglass",
                        description: Text(String(localized: "輸入關鍵字以在 PDF 中尋找內容。"))
                    )
                } else {
                    ContentUnavailableView(
                        String(localized: "沒有結果"),
                        systemImage: "magnifyingglass",
                        description: Text(String(localized: "找不到符合的文字。"))
                    )
                }
            } else {
                HStack {
                    Text(results.count == 1
                         ? String(localized: "1 個結果")
                         : String(localized: "\(results.count) 個結果"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        stepResult(by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(results.isEmpty)
                    Button {
                        stepResult(by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(results.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                List(Array(results.enumerated()), id: \.offset) { index, selection in
                    Button {
                        selectedResultIndex = index
                        onSelect(selection)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selection.string ?? "")
                                .lineLimit(2)
                                .font(.body)
                            if let page = selection.pages.first, let doc = page.document {
                                Text(String(localized: "第 \(doc.index(for: page) + 1) 頁"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(index == selectedResultIndex ? Color.accentColor.opacity(0.12) : nil)
                }
            }
        }
    }

    private func stepResult(by delta: Int) {
        guard !results.isEmpty else { return }
        let next = (selectedResultIndex + delta + results.count) % results.count
        selectedResultIndex = next
        onSelect(results[next])
    }
}
