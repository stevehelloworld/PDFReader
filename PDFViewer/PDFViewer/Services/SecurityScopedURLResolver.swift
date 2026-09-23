import Foundation

/// Creates and resolves security-scoped bookmarks for sandboxed file access.
enum SecurityScopedURLResolver {
    /// Track balanced security-scope acquisitions. A URL can be opened by a new
    /// session before the previous session releases it, so this must be ref-counted.
    private static var activeURLs: [URL: Int] = [:]
    private static let lock = NSLock()

    static func makeBookmark(for url: URL) -> Data? {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        #if os(macOS)
        return try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    /// Resolve a recent file to an accessible URL. Caller must call `stopAccess` when done
    /// if they only need a short-lived open. For long-lived document sessions use `startAccess`
    /// and keep the URL until the document is closed.
    static func resolve(file: RecentFile) -> URL? {
        if let data = file.bookmarkData {
            return resolveBookmark(data)
        }

        let url = URL(fileURLWithPath: file.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return startAccess(url) ? url : nil
    }

    static func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif

        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard startAccess(url) else { return nil }
            return url
        } catch {
            return nil
        }
    }

    @discardableResult
    static func startAccess(_ url: URL) -> Bool {
        let ok = url.startAccessingSecurityScopedResource()
        // For non-scoped URLs (e.g. app container copies), startAccess returns false but path is still valid.
        let usable = ok || FileManager.default.isReadableFile(atPath: url.path)
        if ok {
            let standard = url.standardizedFileURL
            lock.lock()
            activeURLs[standard, default: 0] += 1
            lock.unlock()
        }
        return usable
    }

    static func stopAccess(_ url: URL) {
        let standard = url.standardizedFileURL
        lock.lock()
        let count = activeURLs[standard, default: 0]
        if count > 1 {
            activeURLs[standard] = count - 1
        } else {
            activeURLs.removeValue(forKey: standard)
        }
        lock.unlock()
        if count > 0 {
            url.stopAccessingSecurityScopedResource()
        }
    }

    static func stopAll() {
        lock.lock()
        let urls = activeURLs
        activeURLs.removeAll()
        lock.unlock()
        for (url, count) in urls {
            for _ in 0..<count {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}
