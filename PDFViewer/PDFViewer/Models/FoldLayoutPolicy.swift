/// Layout rules for displays that report a fold (a SwiftUI reserved region of kind
/// `.division`, iOS 27.1+). Open and half-folded postures look the same to the app,
/// so the rules apply whenever a division exists. Pure so it can be unit tested.
enum FoldLayoutPolicy {
    enum Event: Equatable {
        /// Reading mode or the display's division changed.
        case layoutChanged
        /// The user brought the library column back.
        case sidebarOpenedByUser
        /// The user hid the library column again.
        case sidebarClosedByUser
    }

    enum Action: Equatable {
        case none
        /// A two-page spread belongs on the fold, so the library column goes away.
        case collapseSidebar
        /// The user wants the library: give in and read single-page. `restoreLater`
        /// is the pinned spread to bring back when the column closes (nil when auto
        /// layout will bring the spread back by itself).
        case switchToSinglePage(restoreLater: ReadingMode?)
        /// The column closed again: bring back the pinned spread.
        case restore(ReadingMode)
    }

    static func action(
        for event: Event,
        hasDivision: Bool,
        isRegularWidth: Bool,
        mode: ReadingMode,
        sidebarVisible: Bool,
        userPinnedMode: Bool,
        forcedSingleFrom: ReadingMode?
    ) -> Action {
        guard hasDivision, isRegularWidth else { return .none }
        switch event {
        case .layoutChanged:
            return mode.isBookMode && sidebarVisible ? .collapseSidebar : .none
        case .sidebarOpenedByUser:
            return mode.isBookMode ? .switchToSinglePage(restoreLater: userPinnedMode ? mode : nil) : .none
        case .sidebarClosedByUser:
            if let spread = forcedSingleFrom, mode == .singlePage { return .restore(spread) }
            return .none
        }
    }
}
