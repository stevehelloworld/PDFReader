import Testing
import CoreGraphics
@testable import PDFViewer

struct PageSlidePolicyTests {
    func outcome(_ t: CGFloat, _ v: CGFloat = 0, rtl: Bool = false, fwd: Bool = true, back: Bool = true) -> PageSlidePolicy.Outcome {
        PageSlidePolicy.outcome(translationX: t, velocityX: v, pageWidth: 400, isRTL: rtl, canGoForward: fwd, canGoBackward: back)
    }

    @Test func activeOnlyForReduceMotionAtFitPageSinglePageFlow() {
        #expect(PageSlidePolicy.isActive(reduceMotion: true, isContinuous: false, zoom: .fitPage))
        #expect(!PageSlidePolicy.isActive(reduceMotion: false, isContinuous: false, zoom: .fitPage))
        #expect(!PageSlidePolicy.isActive(reduceMotion: true, isContinuous: true, zoom: .fitPage))
        #expect(!PageSlidePolicy.isActive(reduceMotion: true, isContinuous: false, zoom: .percent150))
    }

    @Test func slowDragPastHalfTurns() {
        // QA case: 90% -> 30% of the width, slowly.
        #expect(outcome(-240, -40) == .turnForward)
        #expect(outcome(240, 40) == .turnBackward)
    }

    @Test func shortSlowDragSpringsBack() {
        #expect(outcome(-150, -50) == .cancel)
        #expect(outcome(-200) == .cancel)    // exactly half is not past half
        #expect(outcome(0, -2000) == .cancel)
    }

    @Test func flickTurnsEvenWhenShort() {
        #expect(outcome(-60, -1200) == .turnForward)
        #expect(outcome(60, 900) == .turnBackward)
    }

    @Test func flickBackAgainstTheDragCancels() {
        #expect(outcome(-300, 900) == .cancel)
    }

    @Test func rightToLeftBooksTurnForwardOnRightwardDrag() {
        #expect(outcome(260, rtl: true) == .turnForward)
        #expect(outcome(-260, rtl: true) == .turnBackward)
        #expect(outcome(80, 1000, rtl: true) == .turnForward)
    }

    @Test func noPageThatWaySpringsBackAndResists() {
        #expect(outcome(-300, fwd: false) == .cancel)
        #expect(outcome(300, back: false) == .cancel)
        #expect(PageSlidePolicy.displayedOffset(translationX: -100, isRTL: false, canGoForward: false, canGoBackward: true) == -25)
        #expect(PageSlidePolicy.displayedOffset(translationX: -100, isRTL: false, canGoForward: true, canGoBackward: true) == -100)
        #expect(PageSlidePolicy.displayedOffset(translationX: 100, isRTL: true, canGoForward: false, canGoBackward: true) == 25)
    }
}
