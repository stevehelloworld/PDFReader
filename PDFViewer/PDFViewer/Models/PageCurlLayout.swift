import Foundation

/// Maps PDF pages onto the slots of a page-curl book (iOS reader).
///
/// Slots are in *visual* left-to-right order, the order `UIPageViewController`
/// walks with its before/after data source. A slot holds a 1-based page number,
/// or `nil` for a blank leaf (the inside of the cover, or the back of an odd last page).
///
/// - Single page: one slot per screen, slots are the pages in order.
/// - Two pages: two slots per screen around a middle spine. The cover sits alone
///   (matching `ReadingMode.pageAfterTurn`: 1 | 2-3 | 4-5 …). Left to right the cover
///   is on the right of the spine; right to left the whole strip is mirrored, so the
///   cover is on the left and reading forward walks towards slot 0.
struct PageCurlLayout: Equatable {
    let pageCount: Int
    let mode: ReadingMode
    let slots: [Int?]

    init(pageCount: Int, mode: ReadingMode) {
        self.pageCount = max(0, pageCount)
        self.mode = mode
        guard self.pageCount > 0 else { slots = []; return }
        let pages: [Int?] = (1...self.pageCount).map { $0 }
        guard mode.isBookMode else { slots = pages; return }
        var ltr: [Int?] = [nil] + pages
        if !ltr.count.isMultiple(of: 2) { ltr.append(nil) }
        slots = mode.isRTL ? Array(ltr.reversed()) : ltr
    }

    var slotsPerScreen: Int { mode.isBookMode ? 2 : 1 }
    var screenCount: Int { slots.count / slotsPerScreen }

    /// Screen index (0-based, visual left-to-right) that shows `page`; clamps out-of-range pages.
    func screen(containing page: Int) -> Int? {
        guard pageCount > 0 else { return nil }
        let clamped = min(max(page, 1), pageCount)
        guard let slot = slots.firstIndex(of: clamped) else { return nil }
        return slot / slotsPerScreen
    }

    /// Slot indices on a screen, left to right.
    func slotRange(ofScreen screen: Int) -> Range<Int> {
        let start = screen * slotsPerScreen
        return start..<(start + slotsPerScreen)
    }

    /// Real pages on a screen, ascending.
    func pages(onScreen screen: Int) -> [Int] {
        guard (0..<screenCount).contains(screen) else { return [] }
        return slotRange(ofScreen: screen).compactMap { slots[$0] }.sorted()
    }

    /// The page the reader reports for a screen: the lowest visible page, the same
    /// page PDFView reports as `currentPage` for a two-up spread.
    func representativePage(ofScreen screen: Int) -> Int? {
        pages(onScreen: screen).first
    }

    func page(atSlot slot: Int) -> Int? {
        slots.indices.contains(slot) ? slots[slot] : nil
    }

    /// Which side of a slot's area the spine is on (for aligning pages to it).
    enum SpineEdge { case none, leading, trailing }

    func spineEdge(ofSlot slot: Int) -> SpineEdge {
        guard mode.isBookMode else { return .none }
        return slot.isMultiple(of: 2) ? .trailing : .leading
    }

    /// Screen index to move to for a reading-order turn, or nil at either end.
    func screen(after screen: Int, forward: Bool) -> Int? {
        let visualStep = (forward != mode.isRTL) ? 1 : -1
        let target = screen + visualStep
        return (0..<screenCount).contains(target) ? target : nil
    }

    /// Book-curl paging is used only for discrete pages at fit-page zoom with motion
    /// allowed. Zoomed, continuous, and Reduce Motion use PDFView's own paging.
    static func usesPageCurl(isContinuous: Bool, zoom: ZoomLevel, reduceMotion: Bool) -> Bool {
        !isContinuous && zoom == .fitPage && !reduceMotion
    }
}
