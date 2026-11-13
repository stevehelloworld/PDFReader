import Testing
@testable import PDFViewer

struct FoldLayoutPolicyTests {
    func act(_ e: FoldLayoutPolicy.Event, division: Bool = true, regular: Bool = true, mode: ReadingMode,
             sidebar: Bool, pinned: Bool = false, forced: ReadingMode? = nil) -> FoldLayoutPolicy.Action {
        FoldLayoutPolicy.action(for: e, hasDivision: division, isRegularWidth: regular, mode: mode,
                                sidebarVisible: sidebar, userPinnedMode: pinned, forcedSingleFrom: forced)
    }

    @Test func twoPageWithSidebarOnFoldCollapsesSidebar() {
        #expect(act(.layoutChanged, mode: .twoPagesLTR, sidebar: true) == .collapseSidebar)
        #expect(act(.layoutChanged, mode: .twoPagesRTL, sidebar: true, pinned: true) == .collapseSidebar)
    }

    @Test func singlePageOrHiddenSidebarIsLeftAlone() {
        #expect(act(.layoutChanged, mode: .singlePage, sidebar: true) == .none)
        #expect(act(.layoutChanged, mode: .twoPagesLTR, sidebar: false) == .none)
    }

    @Test func noDivisionOrCompactWidthNeverActs() {
        for e in [FoldLayoutPolicy.Event.layoutChanged, .sidebarOpenedByUser, .sidebarClosedByUser] {
            #expect(act(e, division: false, mode: .twoPagesLTR, sidebar: true, forced: .twoPagesLTR) == .none)
            #expect(act(e, regular: false, mode: .twoPagesLTR, sidebar: true, forced: .twoPagesLTR) == .none)
        }
    }

    @Test func reopeningSidebarSwitchesToSinglePage() {
        // Pinned spread: remember it so closing the column brings it back.
        #expect(act(.sidebarOpenedByUser, mode: .twoPagesRTL, sidebar: true, pinned: true) == .switchToSinglePage(restoreLater: .twoPagesRTL))
        // Auto spread: AutoSpreadPolicy re-spreads on its own.
        #expect(act(.sidebarOpenedByUser, mode: .twoPagesLTR, sidebar: true) == .switchToSinglePage(restoreLater: nil))
        #expect(act(.sidebarOpenedByUser, mode: .singlePage, sidebar: true) == .none)
    }

    @Test func closingSidebarRestoresOnlyAForcedSpread() {
        #expect(act(.sidebarClosedByUser, mode: .singlePage, sidebar: false, pinned: true, forced: .twoPagesRTL) == .restore(.twoPagesRTL))
        #expect(act(.sidebarClosedByUser, mode: .singlePage, sidebar: false, pinned: true) == .none)
        // The user picked another mode meanwhile: keep it.
        #expect(act(.sidebarClosedByUser, mode: .twoPagesLTR, sidebar: false, pinned: true, forced: .twoPagesRTL) == .none)
    }

    @Test func autoSpreadPolicyStillYieldsToManualPick() {
        // Manual wins: the fold policy never pins, and auto spread stays off once pinned.
        #expect(AutoSpreadPolicy.mode(readerWidth: 951, windowWidth: 951, isRegularWidth: true,
                                      userPinnedMode: true, spreadPreference: .singlePage) == nil)
        #expect(AutoSpreadPolicy.mode(readerWidth: 651, windowWidth: 951, isRegularWidth: true,
                                      userPinnedMode: false, spreadPreference: .twoPagesLTR) == .singlePage)
        #expect(AutoSpreadPolicy.mode(readerWidth: 951, windowWidth: 951, isRegularWidth: true,
                                      userPinnedMode: false, spreadPreference: .twoPagesRTL) == .twoPagesRTL)
    }
}
