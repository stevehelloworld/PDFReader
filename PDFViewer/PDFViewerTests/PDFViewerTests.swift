//
//  PDFViewerTests.swift
//  PDFViewerTests
//
//  Created by steveyeh on 2025/7/10.
//

import Testing
import Foundation
import PDFKit
@testable import PDFViewer

struct PDFViewerTests {

    @Test func readingModeRTLFlags() {
        #expect(ReadingMode.twoPagesRTL.isRTL)
        #expect(!ReadingMode.twoPagesLTR.isRTL)
        #expect(!ReadingMode.singlePage.isRTL)
        #expect(ReadingMode.twoPagesLTR.isBookMode)
        #expect(!ReadingMode.singlePage.isBookMode)
    }

    @Test func pageTurnsAdvanceByVisibleSpread() {
        #expect(ReadingMode.twoPagesLTR.pageAfterTurn(from: 1, totalPages: 10, forward: true) == 2)
        #expect(ReadingMode.twoPagesLTR.pageAfterTurn(from: 2, totalPages: 10, forward: true) == 4)
        #expect(ReadingMode.twoPagesLTR.pageAfterTurn(from: 3, totalPages: 10, forward: true) == 4)
        #expect(ReadingMode.twoPagesRTL.pageAfterTurn(from: 4, totalPages: 10, forward: false) == 2)
        #expect(ReadingMode.twoPagesLTR.pageAfterTurn(from: 5, totalPages: 5, forward: true) == nil)
        #expect(ReadingMode.twoPagesLTR.pageAfterTurn(from: 2, totalPages: 5, forward: false) == 1)
        #expect(ReadingMode.twoPagesLTR.pageAfterTurn(from: 3, totalPages: 5, forward: false) == 1)
    }

    @Test @MainActor func modeSwitchCaptureUsesThePDFViewsVisiblePage() {
        let document = PDFDocument()
        for index in 0..<5 {
            document.insert(PDFPage(), at: index)
        }

        let pdfView = PDFView()
        pdfView.document = document
        pdfView.go(to: document.page(at: 3)!)
        let pageSource = PDFViewPageSource()
        pageSource.attach(pdfView)

        #expect(pageSource.currentPageNumber(in: document) == 4)
        pageSource.protect(pageNumber: 4, in: document)
        pageSource.detach(pdfView)

        let recreatedPDFView = PDFView()
        pageSource.attach(recreatedPDFView)
        recreatedPDFView.document = document

        #expect(pageSource.currentPageNumber(in: document) == 4)
        #expect(pageSource.shouldIgnorePageChange(pageNumber: 1, in: document))
        #expect(!pageSource.shouldIgnorePageChange(pageNumber: 4, in: document))

        pageSource.clearPageProtection(in: document)
        #expect(!pageSource.shouldIgnorePageChange(pageNumber: 1, in: document))
    }

    @Test func singlePageTurnsAdvanceOnePage() {
        #expect(ReadingMode.singlePage.pageAfterTurn(from: 2, totalPages: 10, forward: true) == 3)
        #expect(ReadingMode.singlePage.pageAfterTurn(from: 2, totalPages: 10, forward: false) == 1)
        #expect(ReadingMode.singlePage.pageAfterTurn(from: 1, totalPages: 10, forward: false) == nil)
    }

    @Test func zoomPercentageLevelsExcludeFitModes() {
        let levels = ZoomLevel.percentageLevels
        #expect(!levels.contains(.fitPage))
        #expect(!levels.contains(.fitWidth))
        #expect(levels.contains(.percent100))
        #expect(ZoomLevel.percent150.scaleFactor == 1.5)
    }

    @Test func recentFileIDStableWithBookmark() {
        let bm = Data([1, 2, 3, 4, 5])
        let a = RecentFile(path: "/tmp/a.pdf", name: "a.pdf", bookmarkData: bm)
        let b = RecentFile(path: "/other/a.pdf", name: "a.pdf", bookmarkData: bm)
        #expect(a.id == b.id)
    }

    @Test func recentFileProgressFraction() {
        var file = RecentFile(path: "/x", name: "x.pdf", currentPage: 5, totalPages: 10)
        #expect(file.progressFraction == 0.5)
        file.totalPages = 0
        #expect(file.progressFraction == 0)
    }

    @Test func recentFileLegacyDecodeWithoutNewFields() throws {
        let json = """
        {
          "id": "legacy",
          "path": "/docs/book.pdf",
          "name": "book.pdf",
          "lastOpened": 0,
          "currentPage": 3,
          "totalPages": 20,
          "readingMode": "twoPagesRTL"
        }
        """.data(using: .utf8)!

        // Encode date properly for decoder
        struct Payload: Encodable {
            let id: String
            let path: String
            let name: String
            let lastOpened: Date
            let currentPage: Int
            let totalPages: Int
            let readingMode: String
        }
        let data = try JSONEncoder().encode(
            Payload(
                id: "legacy",
                path: "/docs/book.pdf",
                name: "book.pdf",
                lastOpened: Date(),
                currentPage: 3,
                totalPages: 20,
                readingMode: "twoPagesRTL"
            )
        )
        let file = try JSONDecoder().decode(RecentFile.self, from: data)
        #expect(file.currentPage == 3)
        #expect(file.readingMode == "twoPagesRTL")
        #expect(file.isContinuous == false)
        #expect(file.appearance == ReadingAppearance.automatic.rawValue)
        _ = json
    }
}
