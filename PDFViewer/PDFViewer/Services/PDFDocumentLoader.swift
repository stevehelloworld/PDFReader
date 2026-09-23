import Foundation
import PDFKit

struct LoadedPDF {
    let document: PDFDocument
    let url: URL
    let fileName: String
    let bookmarkData: Data?
    let fileID: String
}

enum PDFDocumentLoader {
    /// Load a PDF off the main thread. Security-scoped access is started on the URL and
    /// remains active for the returned session URL — caller must `SecurityScopedURLResolver.stopAccess`
    /// when replacing/closing the document.
    static func load(from url: URL, existingBookmark: Data? = nil) async throws -> LoadedPDF {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let loaded = try Self.loadSync(from: url, existingBookmark: existingBookmark)
                    continuation.resume(returning: loaded)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func load(recent file: RecentFile) async throws -> LoadedPDF {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let url = SecurityScopedURLResolver.resolve(file: file) else {
                        throw PDFError.fileNotFound
                    }
                    // resolve() already started access
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        SecurityScopedURLResolver.stopAccess(url)
                        throw PDFError.fileNotFound
                    }
                    guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                        SecurityScopedURLResolver.stopAccess(url)
                        throw PDFError.invalidPDF
                    }
                    // Recreate the bookmark after every successful resolution so a stale
                    // bookmark doesn't get written back into the recent-file history.
                    let bookmark = SecurityScopedURLResolver.makeBookmark(for: url) ?? file.bookmarkData
                    continuation.resume(returning: LoadedPDF(
                        document: document,
                        url: url,
                        fileName: file.name,
                        bookmarkData: bookmark,
                        fileID: file.id
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func loadSync(from url: URL, existingBookmark: Data?) throws -> LoadedPDF {
        guard SecurityScopedURLResolver.startAccess(url) else {
            throw PDFError.accessDenied
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            SecurityScopedURLResolver.stopAccess(url)
            throw PDFError.fileNotFound
        }

        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            SecurityScopedURLResolver.stopAccess(url)
            throw PDFError.invalidPDF
        }

        let bookmark = SecurityScopedURLResolver.makeBookmark(for: url) ?? existingBookmark
        let name = url.lastPathComponent
        let id = RecentFile.makeID(name: name, path: url.path, bookmarkData: bookmark)

        return LoadedPDF(
            document: document,
            url: url,
            fileName: name,
            bookmarkData: bookmark,
            fileID: id
        )
    }
}
