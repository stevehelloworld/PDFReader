#if os(iOS)
import SwiftUI
import PDFKit
import UIKit

// MARK: - Page renderer (off-main, cached, memory bounded)

/// Renders PDF pages to bitmaps sized for the screen. Rendering runs on one
/// background queue so neighbours are ready before a curl reveals them.
final class PageCurlRenderer {
    let document: PDFDocument
    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "PageCurlRenderer", qos: .userInitiated)
    /// Completions waiting on an in-flight render; main thread only.
    private var waiting: [String: [(UIImage) -> Void]] = [:]
    /// Longest bitmap edge; keeps one page under ~45 MB even on huge pages.
    static let maxPixelEdge: CGFloat = 3600

    init(document: PDFDocument) {
        self.document = document
        // About ten full-screen pages on a Pro Max; NSCache evicts beyond this
        // and on memory warnings.
        cache.totalCostLimit = 160 * 1024 * 1024
        cache.countLimit = 14
    }

    /// Page size in points as displayed (rotation applied).
    func displaySize(of page: Int) -> CGSize? {
        guard let pdfPage = document.page(at: page - 1) else { return nil }
        let box = pdfPage.bounds(for: .cropBox).size
        let quarterTurns = ((pdfPage.rotation % 360) + 360) % 360 / 90
        return quarterTurns.isMultiple(of: 2) ? box : CGSize(width: box.height, height: box.width)
    }

    static func pixelSize(for pointSize: CGSize, scale: CGFloat) -> CGSize {
        var w = (pointSize.width * scale).rounded()
        var h = (pointSize.height * scale).rounded()
        let longest = max(w, h)
        if longest > maxPixelEdge {
            let f = maxPixelEdge / longest
            w = (w * f).rounded(); h = (h * f).rounded()
        }
        return CGSize(width: max(w, 1), height: max(h, 1))
    }

    private func key(_ page: Int, _ px: CGSize) -> String { "\(page)@\(Int(px.width))x\(Int(px.height))" }

    func cachedImage(page: Int, pixelSize: CGSize) -> UIImage? {
        cache.object(forKey: key(page, pixelSize) as NSString)
    }

    /// Main thread. Calls back on the main thread (immediately when cached).
    func image(page: Int, pixelSize: CGSize, completion: @escaping (UIImage) -> Void) {
        let k = key(page, pixelSize)
        if let hit = cache.object(forKey: k as NSString) { completion(hit); return }
        if waiting[k] != nil { waiting[k]?.append(completion); return }
        waiting[k] = [completion]
        guard let pdfPage = document.page(at: page - 1) else { waiting[k] = nil; return }
        queue.async { [weak self] in
            let image = Self.render(pdfPage, pixelSize: pixelSize)
            DispatchQueue.main.async {
                guard let self else { return }
                self.cache.setObject(image, forKey: k as NSString, cost: Self.cost(of: pixelSize))
                let callbacks = self.waiting.removeValue(forKey: k) ?? []
                callbacks.forEach { $0(image) }
            }
        }
    }

    /// Synchronous render for the very first screen so it never shows blank.
    func renderNow(page: Int, pixelSize: CGSize) -> UIImage? {
        if let hit = cachedImage(page: page, pixelSize: pixelSize) { return hit }
        guard let pdfPage = document.page(at: page - 1) else { return nil }
        let image = Self.render(pdfPage, pixelSize: pixelSize)
        cache.setObject(image, forKey: key(page, pixelSize) as NSString, cost: Self.cost(of: pixelSize))
        return image
    }

    func prerender(page: Int, pixelSize: CGSize) {
        image(page: page, pixelSize: pixelSize) { _ in }
    }

    private static func cost(of px: CGSize) -> Int { Int(px.width * px.height * 4) }

    static func render(_ page: PDFPage, pixelSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let bounds = page.bounds(for: .cropBox)
        let quarterTurns = ((page.rotation % 360) + 360) % 360 / 90
        let shown = quarterTurns.isMultiple(of: 2) ? bounds.size : CGSize(width: bounds.height, height: bounds.width)
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: pixelSize))
            let cg = ctx.cgContext
            cg.interpolationQuality = .high
            // Flip into PDF space; PDFPage.draw applies the page's rotation and box origin.
            cg.translateBy(x: 0, y: pixelSize.height)
            cg.scaleBy(x: pixelSize.width / max(shown.width, 1), y: -pixelSize.height / max(shown.height, 1))
            page.draw(with: .cropBox, to: cg)
        }
    }
}

// MARK: - One leaf of the book

final class PageCurlLeafViewController: UIViewController {
    let slot: Int
    let page: Int?
    let spineEdge: PageCurlLayout.SpineEdge
    private let renderer: PageCurlRenderer
    private let imageView = UIImageView()
    private var requestedPixelSize: CGSize = .zero
    var leafBackground: UIColor { didSet { view.backgroundColor = leafBackground } }

    init(slot: Int, page: Int?, spineEdge: PageCurlLayout.SpineEdge, renderer: PageCurlRenderer, background: UIColor) {
        self.slot = slot
        self.page = page
        self.spineEdge = spineEdge
        self.renderer = renderer
        self.leafBackground = background
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = leafBackground
        imageView.contentMode = .scaleToFill
        // Faint page shadow like PDFView's. Path-based (shadowPath set in layout), so no
        // offscreen pass; the image fills the frame exactly, so no clipping is needed.
        imageView.clipsToBounds = false
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOpacity = 0.18
        imageView.layer.shadowRadius = 3
        imageView.layer.shadowOffset = CGSize(width: 0, height: 1)
        imageView.isAccessibilityElement = false
        view.addSubview(imageView)
    }

    /// Aspect-fit frame of the page inside `bounds`, pushed against the spine.
    static func pageFrame(pageSize: CGSize, in bounds: CGRect, spineEdge: PageCurlLayout.SpineEdge) -> CGRect {
        guard pageSize.width > 0, pageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let s = min(bounds.width / pageSize.width, bounds.height / pageSize.height)
        let size = CGSize(width: (pageSize.width * s).rounded(.down), height: (pageSize.height * s).rounded(.down))
        let y = bounds.minY + ((bounds.height - size.height) / 2).rounded()
        let x: CGFloat
        switch spineEdge {
        case .none: x = bounds.minX + ((bounds.width - size.width) / 2).rounded()
        case .trailing: x = bounds.maxX - size.width
        case .leading: x = bounds.minX
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    func fittedPointSize(in bounds: CGRect) -> CGSize? {
        guard let page, let size = renderer.displaySize(of: page) else { return nil }
        return Self.pageFrame(pageSize: size, in: bounds, spineEdge: spineEdge).size
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let page, let size = renderer.displaySize(of: page) else { imageView.frame = .zero; return }
        let frame = Self.pageFrame(pageSize: size, in: view.bounds, spineEdge: spineEdge)
        imageView.frame = frame
        imageView.layer.shadowPath = UIBezierPath(rect: imageView.bounds).cgPath
        let scale = view.window?.screen.scale ?? traitCollection.displayScale
        let px = PageCurlRenderer.pixelSize(for: frame.size, scale: max(scale, 1))
        guard px != requestedPixelSize, frame.width > 1 else { return }
        requestedPixelSize = px
        if let hit = renderer.cachedImage(page: page, pixelSize: px) {
            imageView.image = hit
        } else {
            renderer.image(page: page, pixelSize: px) { [weak self] image in
                guard let self, self.requestedPixelSize == px else { return }
                self.imageView.image = image
            }
        }
    }

    /// First screen: draw synchronously so the reader never opens blank.
    func renderSynchronouslyIfNeeded(in bounds: CGRect, scale: CGFloat) {
        guard imageView.image == nil, let page, let size = fittedPointSize(in: bounds) else { return }
        let px = PageCurlRenderer.pixelSize(for: size, scale: scale)
        imageView.image = renderer.renderNow(page: page, pixelSize: px)
        requestedPixelSize = px
    }
}

// MARK: - Accessible container view

final class PageCurlContainerView: UIView {
    var onIncrement: (() -> Void)?
    var onDecrement: (() -> Void)?
    override func accessibilityIncrement() { onIncrement?() }
    override func accessibilityDecrement() { onDecrement?() }
}

// MARK: - Book controller

/// Hosts a `UIPageViewController(.pageCurl)` and keeps it on the requested page.
final class PageCurlBookViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
    private(set) var renderer: PageCurlRenderer
    private(set) var layout: PageCurlLayout
    private var pageController: UIPageViewController!
    private(set) var displayedScreen: Int = 0
    private var isUserTurning = false
    private var isAnimatingProgrammatic = false
    private var pendingPage: Int?
    private var lastPrerenderKey = ""

    var leafBackground: UIColor = .systemBackground {
        didSet {
            guard leafBackground != oldValue else { return }
            view.backgroundColor = leafBackground
            pageController?.viewControllers?.forEach { ($0 as? PageCurlLeafViewController)?.leafBackground = leafBackground }
        }
    }
    /// Reading-order page the user settled on (lowest visible page).
    var onPageSettled: ((Int) -> Void)?
    var onSingleTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    /// Pinch-out: the reader hands over to PDFView at this zoom.
    var onZoomRequest: ((ZoomLevel) -> Void)?

    var document: PDFDocument { renderer.document }

    init(document: PDFDocument, mode: ReadingMode, page: Int) {
        renderer = PageCurlRenderer(document: document)
        layout = PageCurlLayout(pageCount: document.pageCount, mode: mode)
        displayedScreen = layout.screen(containing: page) ?? 0
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let container = PageCurlContainerView()
        container.isAccessibilityElement = true
        container.accessibilityTraits = [.adjustable]
        container.accessibilityIdentifier = "PageCurlReader"
        container.onIncrement = { [weak self] in self?.turn(forward: true) }
        container.onDecrement = { [weak self] in self?.turn(forward: false) }
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = leafBackground
        installPageController()

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        view.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        singleTap.delegate = self
        view.addGestureRecognizer(singleTap)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)
    }

    private func installPageController() {
        if let old = pageController {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        let spine: UIPageViewController.SpineLocation = layout.mode.isBookMode ? .mid : .min
        let pvc = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: spine.rawValue)]
        )
        pvc.isDoubleSided = layout.mode.isBookMode
        pvc.dataSource = self
        pvc.delegate = self
        // Leaves must be in place before the view reaches a window: UIPageViewController
        // asks for the spine (see spineLocationFor) in viewWillAppear.
        if layout.screenCount > 0 {
            pvc.setViewControllers(leaves(forScreen: displayedScreen), direction: .forward, animated: false)
        }
        addChild(pvc)
        pvc.view.frame = view.bounds
        pvc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pvc.view.backgroundColor = .clear
        view.addSubview(pvc.view)
        pvc.didMove(toParent: self)
        // Taps belong to the reader (chrome toggle / double tap), not to edge page turns.
        for recognizer in pvc.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }
        pageController = pvc
    }

    private func leaves(forScreen screen: Int) -> [UIViewController] {
        layout.slotRange(ofScreen: screen).map(leaf(forSlot:))
    }

    private func leaf(forSlot slot: Int) -> PageCurlLeafViewController {
        PageCurlLeafViewController(
            slot: slot,
            page: layout.page(atSlot: slot),
            spineEdge: layout.spineEdge(ofSlot: slot),
            renderer: renderer,
            background: leafBackground
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let scale = view.window?.screen.scale ?? traitCollection.displayScale
        if let leaves = pageController.viewControllers as? [PageCurlLeafViewController] {
            for leafVC in leaves {
                leafVC.renderSynchronouslyIfNeeded(in: leafBounds, scale: max(scale, 1))
            }
        }
        prerenderNeighbours()
        updateAccessibility()
    }

    /// Area one leaf occupies: full width, or half of it around the spine.
    private var leafBounds: CGRect {
        let b = view.bounds
        return layout.mode.isBookMode ? CGRect(x: 0, y: 0, width: b.width / 2, height: b.height) : b
    }

    /// Prerender the previous and next screen at the size they will be shown.
    private func prerenderNeighbours() {
        let scale = max(view.window?.screen.scale ?? traitCollection.displayScale, 1)
        let bounds = leafBounds
        guard bounds.width > 1 else { return }
        let key = "\(displayedScreen)-\(Int(bounds.width))x\(Int(bounds.height))@\(scale)"
        guard key != lastPrerenderKey else { return }
        lastPrerenderKey = key
        for screen in [displayedScreen + 1, displayedScreen - 1, displayedScreen + 2, displayedScreen - 2]
        where (0..<layout.screenCount).contains(screen) {
            for slot in layout.slotRange(ofScreen: screen) {
                guard let page = layout.page(atSlot: slot), let size = renderer.displaySize(of: page) else { continue }
                let frame = PageCurlLeafViewController.pageFrame(pageSize: size, in: bounds, spineEdge: layout.spineEdge(ofSlot: slot))
                renderer.prerender(page: page, pixelSize: PageCurlRenderer.pixelSize(for: frame.size, scale: scale))
            }
        }
    }

    private func updateAccessibility() {
        let pages = layout.pages(onScreen: displayedScreen)
        let label = pages.map(String.init).joined(separator: "–")
        view.accessibilityLabel = String(localized: "第 \(label) 頁，共 \(layout.pageCount) 頁")
        view.accessibilityValue = label
    }

    // MARK: Navigation

    /// Shows the screen containing `page`. Adjacent screens curl; jumps do not.
    func show(page: Int) {
        if pendingReset != nil { pendingReset?.page = page; return }
        guard let target = layout.screen(containing: page), target != displayedScreen else { return }
        guard !isUserTurning, !isAnimatingProgrammatic else { pendingPage = page; return }
        let adjacent = abs(target - displayedScreen) == 1 && view.window != nil && !UIAccessibility.isReduceMotionEnabled
        let direction: UIPageViewController.NavigationDirection = target > displayedScreen ? .forward : .reverse
        displayedScreen = target
        pendingPage = nil
        if adjacent {
            isAnimatingProgrammatic = true
            pageController.setViewControllers(leaves(forScreen: target), direction: direction, animated: true) { [weak self] _ in
                guard let self else { return }
                self.isAnimatingProgrammatic = false
                self.didSettle(notify: false)
                if let next = self.pendingPage { self.show(page: next) }
            }
        } else {
            pageController.setViewControllers(leaves(forScreen: target), direction: direction, animated: false)
            didSettle(notify: false)
        }
    }

    func turn(forward: Bool) {
        guard let target = layout.screen(after: displayedScreen, forward: forward),
              let page = layout.representativePage(ofScreen: target) else { return }
        show(page: page)
        onPageSettled?(page)
    }

    private var isInSizeTransition = false
    private var pendingReset: (document: PDFDocument, mode: ReadingMode, page: Int)?

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        isInSizeTransition = true
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            self.isInSizeTransition = false
            if let r = self.pendingReset {
                self.pendingReset = nil
                DispatchQueue.main.async { self.reset(document: r.document, mode: r.mode, page: r.page) }
            }
        }
    }

    /// Mode the book shows, or will show once a pending rebuild runs.
    var targetMode: ReadingMode { pendingReset?.mode ?? layout.mode }

    /// Rebuilds for a new document or mode, keeping `page`. Swapping the child page
    /// controller mid-rotation leaves UIKit's transition unfinished, so a rebuild
    /// requested during a size transition waits for it to complete.
    func reset(document: PDFDocument, mode: ReadingMode, page: Int) {
        if isInSizeTransition {
            pendingReset = (document, mode, page)
            return
        }
        // Also catches transitions this controller was not told about (SwiftUI may
        // update the representable from inside the rotation's animation block).
        if let coordinator = transitionCoordinator ?? parent?.transitionCoordinator {
            pendingReset = (document, mode, page)
            isInSizeTransition = true
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                guard let self else { return }
                self.isInSizeTransition = false
                if let r = self.pendingReset {
                    self.pendingReset = nil
                    DispatchQueue.main.async { self.reset(document: r.document, mode: r.mode, page: r.page) }
                }
            }
            return
        }
        UIView.performWithoutAnimation { rebuild(document: document, mode: mode, page: page) }
    }

    private func rebuild(document: PDFDocument, mode: ReadingMode, page: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if document !== renderer.document { renderer = PageCurlRenderer(document: document) }
        layout = PageCurlLayout(pageCount: document.pageCount, mode: mode)
        displayedScreen = layout.screen(containing: page) ?? 0
        lastPrerenderKey = ""
        isUserTurning = false
        isAnimatingProgrammatic = false
        installPageController()
        view.setNeedsLayout()
    }

    private func didSettle(notify: Bool) {
        prerenderNeighbours()
        updateAccessibility()
        UIAccessibility.post(notification: .pageScrolled, argument: view.accessibilityLabel)
        if notify, let page = layout.representativePage(ofScreen: displayedScreen) {
            onPageSettled?(page)
        }
    }

    // MARK: UIPageViewControllerDataSource

    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let leafVC = viewController as? PageCurlLeafViewController, leafVC.slot > 0 else { return nil }
        return leaf(forSlot: leafVC.slot - 1)
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let leafVC = viewController as? PageCurlLeafViewController, leafVC.slot + 1 < layout.slots.count else { return nil }
        return leaf(forSlot: leafVC.slot + 1)
    }

    // MARK: UIPageViewControllerDelegate

    /// Called when the page controller appears and on every interface rotation. Without
    /// it UIKit falls back to a .min spine, which breaks a double-sided .mid book
    /// (mismatched leaf count; the rotation never finishes). Keep our spine and leaves.
    func pageViewController(_ pvc: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation {
        let isBook = layout.mode.isBookMode
        pvc.isDoubleSided = isBook
        if layout.screenCount > 0 {
            pvc.setViewControllers(leaves(forScreen: displayedScreen), direction: .forward, animated: false)
        }
        return isBook ? .mid : .min
    }

    func pageViewController(_ pvc: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        isUserTurning = true
    }

    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        isUserTurning = false
        if completed, let first = (pvc.viewControllers?.first as? PageCurlLeafViewController) {
            displayedScreen = first.slot / layout.slotsPerScreen
            didSettle(notify: true)
        }
        // A cancelled drag leaves the screen as it was.
        if let next = pendingPage { show(page: next) }
    }

    // MARK: Gestures

    @objc private func handleSingleTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, !isUserTurning else { return }
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, !isUserTurning else { return }
        onDoubleTap?()
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard g.state == .changed, g.scale > 1.15 else { return }
        g.isEnabled = false
        g.isEnabled = true
        onZoomRequest?(zoomLevelForPinchOut())
    }

    /// The first preset zoom clearly larger than the current fit-page scale.
    private func zoomLevelForPinchOut() -> ZoomLevel {
        guard let page = layout.representativePage(ofScreen: displayedScreen),
              let size = renderer.displaySize(of: page) else { return .percent150 }
        let b = leafBounds
        let fit = min(b.width / max(size.width, 1), b.height / max(size.height, 1))
        return ZoomLevel.percentageLevels.first { ($0.scaleFactor ?? 0) >= fit * 1.25 } ?? .percent200
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        g is UIPinchGestureRecognizer
    }
}

// MARK: - SwiftUI wrapper

/// Book-style page-curl reader for fit-page, non-continuous reading on iOS.
struct PageCurlReaderView: UIViewControllerRepresentable {
    let document: PDFDocument
    let pageSource: PDFViewPageSource
    let readingMode: ReadingMode
    @Binding var currentPage: Int
    @Binding var pageInputText: String
    @Binding var zoomLevel: ZoomLevel
    let appearance: ReadingAppearance
    var pendingSelection: PDFSelection?
    var onSelectionConsumed: () -> Void
    var onSingleTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?

    static func background(for appearance: ReadingAppearance) -> UIColor {
        switch appearance {
        case .automatic, .light: return .systemBackground
        case .sepia: return UIColor(red: 0.96, green: 0.93, blue: 0.85, alpha: 1)
        case .night, .inverted: return UIColor(white: 0.12, alpha: 1)
        }
    }

    func makeUIViewController(context: Context) -> PageCurlBookViewController {
        let page = currentPage
        let book = PageCurlBookViewController(document: document, mode: readingMode, page: page)
        pageSource.remember(pageNumber: min(max(page, 1), max(document.pageCount, 1)), in: document)
        return book
    }

    func updateUIViewController(_ book: PageCurlBookViewController, context: Context) {
        let source = pageSource
        let doc = document
        let page = $currentPage
        let field = $pageInputText
        let zoom = $zoomLevel
        book.onPageSettled = { settled in
            source.clearPageProtection(in: doc)
            source.remember(pageNumber: settled, in: doc)
            if page.wrappedValue != settled { page.wrappedValue = settled }
            if field.wrappedValue != "\(settled)" { field.wrappedValue = "\(settled)" }
        }
        book.onSingleTap = onSingleTap
        book.onDoubleTap = onDoubleTap
        book.onZoomRequest = { level in zoom.wrappedValue = level }
        book.leafBackground = Self.background(for: appearance)

        if book.document !== document || book.targetMode != readingMode {
            book.reset(document: document, mode: readingMode, page: currentPage)
        }
        if let selection = pendingSelection {
            if let first = selection.pages.first {
                let target = document.index(for: first) + 1
                book.show(page: target)
                pageSource.remember(pageNumber: target, in: document)
            }
            DispatchQueue.main.async { onSelectionConsumed() }
        } else if (1...max(document.pageCount, 1)).contains(currentPage) {
            book.show(page: currentPage)
            pageSource.remember(pageNumber: currentPage, in: document)
        }
    }
}
#endif
