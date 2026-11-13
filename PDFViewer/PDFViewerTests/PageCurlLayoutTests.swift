import Testing
import CoreGraphics
@testable import PDFViewer

struct PageCurlLayoutTests {

    @Test func singlePageSlotsArePagesInOrder() {
        let layout = PageCurlLayout(pageCount: 5, mode: .singlePage)
        #expect(layout.slots == [1, 2, 3, 4, 5])
        #expect(layout.screenCount == 5)
        #expect(layout.screen(containing: 3) == 2)
        #expect(layout.pages(onScreen: 2) == [3])
        #expect(layout.spineEdge(ofSlot: 0) == .none)
    }

    @Test func twoPageLTRCoverSitsRightOfSpine() {
        // 6 pages: [_ 1] [2 3] [4 5] [6 _]
        let layout = PageCurlLayout(pageCount: 6, mode: .twoPagesLTR)
        #expect(layout.slots == [nil, 1, 2, 3, 4, 5, 6, nil])
        #expect(layout.screenCount == 4)
        #expect(layout.pages(onScreen: 0) == [1])
        #expect(layout.pages(onScreen: 1) == [2, 3])
        #expect(layout.pages(onScreen: 3) == [6])
        #expect(layout.screen(containing: 3) == 1)
        #expect(layout.representativePage(ofScreen: 1) == 2)
        #expect(layout.spineEdge(ofSlot: 2) == .trailing)
        #expect(layout.spineEdge(ofSlot: 3) == .leading)
    }

    @Test func twoPageOddCountNeedsNoTrailingBlank() {
        // 5 pages: [_ 1] [2 3] [4 5]
        let layout = PageCurlLayout(pageCount: 5, mode: .twoPagesLTR)
        #expect(layout.slots == [nil, 1, 2, 3, 4, 5])
        #expect(layout.pages(onScreen: 2) == [4, 5])
    }

    @Test func twoPageRTLIsMirrored() {
        // RTL, 6 pages, left to right: [_ 6] [5 4] [3 2] [1 _]
        let layout = PageCurlLayout(pageCount: 6, mode: .twoPagesRTL)
        #expect(layout.slots == [nil, 6, 5, 4, 3, 2, 1, nil])
        #expect(layout.screen(containing: 1) == 3)
        #expect(layout.pages(onScreen: 2) == [2, 3])
        // Right-hand page of a spread is the earlier page.
        #expect(layout.page(atSlot: 5) == 2)
        #expect(layout.page(atSlot: 4) == 3)
        // Reading forward walks to the left.
        #expect(layout.screen(after: 3, forward: true) == 2)
        #expect(layout.screen(after: 0, forward: true) == nil)
        #expect(layout.screen(after: 3, forward: false) == nil)
    }

    @Test func spreadsMatchPageTurnModel() {
        // Every screen's representative page is what pageAfterTurn walks through.
        for mode in [ReadingMode.twoPagesLTR, .twoPagesRTL, .singlePage] {
            for count in [1, 2, 3, 6, 7] {
                let layout = PageCurlLayout(pageCount: count, mode: mode)
                var page = 1
                var screen = layout.screen(containing: 1)!
                while let next = mode.pageAfterTurn(from: page, totalPages: count, forward: true) {
                    screen = layout.screen(after: screen, forward: true)!
                    #expect(layout.representativePage(ofScreen: screen) == next, "\(mode) \(count) after \(page)")
                    page = next
                }
                #expect(layout.screen(after: screen, forward: true) == nil)
            }
        }
    }

    @Test func emptyAndClampedPages() {
        let empty = PageCurlLayout(pageCount: 0, mode: .twoPagesLTR)
        #expect(empty.slots.isEmpty)
        #expect(empty.screen(containing: 1) == nil)
        let layout = PageCurlLayout(pageCount: 3, mode: .singlePage)
        #expect(layout.screen(containing: 99) == 2)
        #expect(layout.screen(containing: -4) == 0)
    }

    @Test func curlOnlyAtFitPageDiscreteWithMotion() {
        #expect(PageCurlLayout.usesPageCurl(isContinuous: false, zoom: .fitPage, reduceMotion: false))
        #expect(!PageCurlLayout.usesPageCurl(isContinuous: true, zoom: .fitPage, reduceMotion: false))
        #expect(!PageCurlLayout.usesPageCurl(isContinuous: false, zoom: .percent150, reduceMotion: false))
        #expect(!PageCurlLayout.usesPageCurl(isContinuous: false, zoom: .fitWidth, reduceMotion: false))
        #expect(!PageCurlLayout.usesPageCurl(isContinuous: false, zoom: .fitPage, reduceMotion: true))
    }

    #if os(iOS)
    @Test func spreadPagesHugTheSpine() {
        let page = CGSize(width: 100, height: 200)
        let half = CGRect(x: 0, y: 0, width: 300, height: 400)
        let left = PageCurlLeafViewController.pageFrame(pageSize: page, in: half, spineEdge: .trailing)
        let right = PageCurlLeafViewController.pageFrame(pageSize: page, in: half, spineEdge: .leading)
        let single = PageCurlLeafViewController.pageFrame(pageSize: page, in: half, spineEdge: .none)
        #expect(left == CGRect(x: 100, y: 0, width: 200, height: 400))
        #expect(right == CGRect(x: 0, y: 0, width: 200, height: 400))
        #expect(single.midX == half.midX)
    }

    @Test func renderSizeIsBounded() {
        let px = PageCurlRenderer.pixelSize(for: CGSize(width: 2000, height: 3000), scale: 3)
        #expect(max(px.width, px.height) <= PageCurlRenderer.maxPixelEdge)
        #expect(PageCurlRenderer.pixelSize(for: CGSize(width: 100, height: 50), scale: 2) == CGSize(width: 200, height: 100))
    }
    #endif
}
