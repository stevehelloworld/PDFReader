import CoreGraphics

/// Reduce Motion page turning in PDFView: the page follows the finger horizontally
/// and slides (no curl). Pure so the release decision can be unit tested.
enum PageSlidePolicy {
    /// A release faster than this (points/second) in the drag's direction turns the page.
    static let flickVelocity: CGFloat = 600
    /// Share of the drag shown when there is no page in that direction.
    static let rubberBand: CGFloat = 0.25

    /// The slide replaces the curl exactly where the curl would otherwise be used.
    static func isActive(reduceMotion: Bool, isContinuous: Bool, zoom: ZoomLevel) -> Bool {
        reduceMotion && !isContinuous && zoom == .fitPage
    }

    enum Outcome: Equatable {
        case turnForward, turnBackward, cancel
    }

    /// Forward means the next page in document order: a leftward drag, or a rightward
    /// drag in right-to-left books.
    static func isForward(translationX: CGFloat, isRTL: Bool) -> Bool {
        (translationX < 0) != isRTL
    }

    /// Release: turn when the page moved past half its width or was flicked the same
    /// way; a flick back against the drag, or no page that way, springs back.
    static func outcome(
        translationX: CGFloat,
        velocityX: CGFloat,
        pageWidth: CGFloat,
        isRTL: Bool,
        canGoForward: Bool,
        canGoBackward: Bool
    ) -> Outcome {
        guard pageWidth > 0, translationX != 0 else { return .cancel }
        let fast = abs(velocityX) > flickVelocity
        let sameWay = (velocityX < 0) == (translationX < 0)
        if fast && !sameWay { return .cancel }
        guard abs(translationX) > pageWidth / 2 || (fast && sameWay) else { return .cancel }
        if isForward(translationX: translationX, isRTL: isRTL) {
            return canGoForward ? .turnForward : .cancel
        }
        return canGoBackward ? .turnBackward : .cancel
    }

    /// Offset to show while dragging: follows the finger, resisting at the first/last page.
    static func displayedOffset(translationX: CGFloat, isRTL: Bool, canGoForward: Bool, canGoBackward: Bool) -> CGFloat {
        let allowed = isForward(translationX: translationX, isRTL: isRTL) ? canGoForward : canGoBackward
        return allowed ? translationX : translationX * rubberBand
    }
}
