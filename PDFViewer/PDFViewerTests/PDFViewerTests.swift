//
//  PDFViewerTests.swift
//  PDFViewerTests
//
//  Created by steveyeh on 2025/7/10.
//

import Testing
import Foundation
@testable import PDFViewer

struct PDFViewerTests {

    @Test func readingModeRTLFlags() {
        #expect(ReadingMode.twoPagesRTL.isRTL)
        #expect(!ReadingMode.twoPagesLTR.isRTL)
        #expect(!ReadingMode.singlePage.isRTL)
        #expect(ReadingMode.twoPagesLTR.isBookMode)
        #expect(!ReadingMode.singlePage.isBookMode)
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
