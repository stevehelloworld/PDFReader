import Foundation
import PDFKit

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class PDFHistoryManager: ObservableObject {
    static let shared = PDFHistoryManager()

    @Published var recentFiles: [RecentFile] = []

    private let maxRecentFiles = 12
    private let recentFilesKey = "recentPDFFiles_v2"
    private let legacyKey = "recentPDFFiles"
    private let thumbnailCache = NSCache<NSString, PlatformImage>()
    private let pageThumbnailCache = NSCache<NSString, PlatformImage>()

    init() {
        thumbnailCache.countLimit = 40
        pageThumbnailCache.countLimit = 120
        loadRecentFiles()
    }

    func loadRecentFiles() {
        if let data = UserDefaults.standard.data(forKey: recentFilesKey),
           let decoded = try? JSONDecoder().decode([RecentFile].self, from: data) {
            recentFiles = decoded.sorted { $0.lastOpened > $1.lastOpened }
            return
        }

        // Migrate legacy recents (name-as-id, no bookmarks).
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode([LegacyRecentFile].self, from: data) {
            recentFiles = legacy.map {
                RecentFile(
                    path: $0.path,
                    name: $0.name,
                    currentPage: $0.currentPage,
                    totalPages: $0.totalPages,
                    readingMode: ReadingMode(rawValue: $0.readingMode) ?? .singlePage,
                    id: $0.id
                )
            }
            saveRecentFiles()
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }

    func saveRecentFiles() {
        if let encoded = try? JSONEncoder().encode(recentFiles) {
            UserDefaults.standard.set(encoded, forKey: recentFilesKey)
        }
    }

    func addRecentFile(_ file: RecentFile) {
        recentFiles.removeAll { matches($0, file) }
        // Keep newest first with fresh lastOpened via re-init fields already set.
        recentFiles.insert(file, at: 0)
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }
        saveRecentFiles()
    }

    func updateProgress(
        id: String,
        currentPage: Int,
        totalPages: Int,
        readingMode: ReadingMode,
        isContinuous: Bool,
        appearance: ReadingAppearance,
        zoomLevel: ZoomLevel
    ) {
        guard let index = recentFiles.firstIndex(where: { $0.id == id }) else { return }
        recentFiles[index].currentPage = currentPage
        recentFiles[index].totalPages = totalPages
        recentFiles[index].readingMode = readingMode.rawValue
        recentFiles[index].isContinuous = isContinuous
        recentFiles[index].appearance = appearance.rawValue
        recentFiles[index].zoomLevel = zoomLevel.rawValue
        saveRecentFiles()
    }

    func getProgress(id: String) -> RecentFile? {
        recentFiles.first { $0.id == id }
    }

    func getProgress(id: String, matching url: URL) -> RecentFile? {
        if let exactMatch = getProgress(id: id) { return exactMatch }

        let requestedPath = normalizedPath(url.path)
        return recentFiles.first { normalizedPath($0.path) == requestedPath }
    }

    func removeFile(id: String) {
        recentFiles.removeAll { $0.id == id }
        thumbnailCache.removeObject(forKey: id as NSString)
        saveRecentFiles()
    }

    func clearAll() {
        recentFiles.removeAll()
        thumbnailCache.removeAllObjects()
        saveRecentFiles()
    }

    // MARK: - Thumbnails for recents

    func cachedThumbnail(for file: RecentFile) -> PlatformImage? {
        thumbnailCache.object(forKey: file.id as NSString)
    }

    func storeThumbnail(_ image: PlatformImage, for fileID: String) {
        thumbnailCache.setObject(image, forKey: fileID as NSString)
    }

    func cachedPageThumbnail(for key: String) -> PlatformImage? {
        pageThumbnailCache.object(forKey: key as NSString)
    }

    func storePageThumbnail(_ image: PlatformImage, for key: String) {
        pageThumbnailCache.setObject(image, forKey: key as NSString)
    }

    func pageThumbnailCacheKey(for url: URL, pageIndex: Int) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modificationTime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        return "\(normalizedPath(url.path))|\(modificationTime)|\(fileSize)|\(pageIndex)"
    }

    func generateThumbnail(for file: RecentFile, size: CGSize = CGSize(width: 80, height: 110)) async -> PlatformImage? {
        if let cached = cachedThumbnail(for: file) { return cached }

        let resolved = await Task.detached(priority: .utility) { () -> PlatformImage? in
            guard let url = SecurityScopedURLResolver.resolve(file: file) else { return nil }
            defer { SecurityScopedURLResolver.stopAccess(url) }

            guard let document = PDFDocument(url: url),
                  let page = document.page(at: max(0, file.currentPage - 1)) ?? document.page(at: 0)
            else { return nil }

            return page.thumbnail(of: size, for: .mediaBox)
        }.value

        if let resolved {
            storeThumbnail(resolved, for: file.id)
        }
        return resolved
    }

    private func matches(_ a: RecentFile, _ b: RecentFile) -> Bool {
        if a.id == b.id { return true }
        return !a.path.isEmpty && !b.path.isEmpty && normalizedPath(a.path) == normalizedPath(b.path)
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

// MARK: - Legacy decode

private struct LegacyRecentFile: Codable {
    let id: String
    let path: String
    let name: String
    let lastOpened: Date
    var currentPage: Int
    var totalPages: Int
    var readingMode: String
}

// MARK: - Platform image typealias

#if os(iOS)
typealias PlatformImage = UIImage
#elseif os(macOS)
typealias PlatformImage = NSImage
#endif
