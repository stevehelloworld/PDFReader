import CoreGraphics

/// Decides whether the iOS reader should switch between single and two-page
/// layout on its own. Pure so it can be unit tested.
enum AutoSpreadPolicy {
    /// Reader column must be at least this wide (points) for an automatic spread.
    static let minimumSpreadWidth: CGFloat = 700
    /// A sidebar that takes less than this from the window is treated as hidden
    /// (overlay sidebars do not shrink the reader).
    static let sidebarTolerance: CGFloat = 40

    /// - Returns: the mode to switch to, or `nil` when auto layout must not act
    ///   (the user picked a mode, or the width class gives no opinion).
    static func mode(
        readerWidth: CGFloat,
        windowWidth: CGFloat,
        isRegularWidth: Bool,
        userPinnedMode: Bool,
        spreadPreference: ReadingMode
    ) -> ReadingMode? {
        guard !userPinnedMode, isRegularWidth, readerWidth > 0 else { return nil }
        let sidebarVisible = windowWidth - readerWidth > sidebarTolerance
        if !sidebarVisible, readerWidth >= minimumSpreadWidth {
            return spreadPreference.isBookMode ? spreadPreference : .twoPagesLTR
        }
        return .singlePage
    }
}
