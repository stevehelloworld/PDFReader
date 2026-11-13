#if os(iOS)
import XCTest

/// Reduce Motion page turning (PDFView, no curl): the page follows a slow drag, turns
/// when released past half its width or flicked, springs back otherwise; RTL turns forward
/// on a rightward drag. Needs Reduce Motion on in the simulator (duo-tools/rm.sh sets it);
/// skips otherwise. Env (TEST_RUNNER_ prefix): QA_SAMPLE_PDF, QA_OUT, QA_MARKERS.
final class ReduceMotionSlideUITests: XCTestCase {
    var env: [String: String] { ProcessInfo.processInfo.environment }
    var out: String { env["QA_OUT"] ?? "/tmp/comicp1-rm" }
    var app: XCUIApplication!
    var samplePath: String { env["QA_SAMPLE_PDF"] ?? "/Users/steveyeh/Projects/PDFviewer/duo-tools/sample.pdf" }

    func recentsArgument() throws -> String {
        let entry: [String: Any] = [
            "id": "qa-sample", "path": samplePath, "name": (samplePath as NSString).lastPathComponent,
            "lastOpened": 815000000.0, "currentPage": 1, "totalPages": 6, "readingMode": "singlePage",
            "isContinuous": false, "appearance": "automatic", "zoomLevel": "fitPage",
        ]
        let json = try JSONSerialization.data(withJSONObject: [entry], options: [.sortedKeys])
        return "<" + json.map { String(format: "%02x", $0) }.joined() + ">"
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/rm-\(name).png"))
    }

    var page: String { app.textFields.firstMatch.value as? String ?? "?" }
    var pdfReader: XCUIElement { app.descendants(matching: .any)["PDFReader"].firstMatch }

    func point(_ x: CGFloat, _ y: CGFloat = 0.42) -> XCUICoordinate {
        pdfReader.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    /// Slow drag (about 3 s for 60% of an iPhone width; velocity is in pixels/s) that stops
    /// before release, so only the distance decides.
    func slowDrag(_ from: CGFloat, _ to: CGFloat, hold: TimeInterval = 0.4) {
        point(from).press(forDuration: 0.2, thenDragTo: point(to), withVelocity: XCUIGestureVelocity(rawValue: 260), thenHoldForDuration: hold)
        sleep(2)
    }

    /// Holds mid-drag so the host watcher can capture the page following the finger.
    func holdMidDrag(_ name: String, from: CGFloat, to: CGFloat) {
        if let dir = env["QA_MARKERS"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? name.write(toFile: "\(dir)/\(name)", atomically: true, encoding: .utf8)
        }
        slowDrag(from, to, hold: 3.5)
    }

    func pick(_ mode: String) {
        let b = app.buttons[mode].firstMatch
        if b.exists && b.isHittable { b.tap() } else {
            app.buttons["閱讀設定"].firstMatch.tap(); sleep(1); app.buttons[mode].firstMatch.tap()
        }
        sleep(2)
    }

    @MainActor func testSlideFollowsFingerAndDecidesOnRelease() throws {
        app = XCUIApplication()
        app.launchArguments = ["-recentPDFFiles_v2", try recentsArgument()]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'sample'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap(); sleep(3)
        if app.descendants(matching: .any)["PageCurlReader"].exists {
            throw XCTSkip("Reduce Motion is off in this simulator (curl reader shown)")
        }
        XCTAssertTrue(pdfReader.waitForExistence(timeout: 5), "PDFView reader missing")
        XCTAssertEqual(page, "1"); shot("01-p1")

        // QA case: slow 3 s drag from 90% to 30% of the width turns forward.
        slowDrag(0.9, 0.3); XCTAssertEqual(page, "2", "slow drag past half must turn"); shot("02-p2")
        // Slow short drag springs back.
        slowDrag(0.9, 0.65); XCTAssertEqual(page, "2", "short slow drag must spring back")
        // Back with a slow rightward drag.
        slowDrag(0.15, 0.8); XCTAssertEqual(page, "1", "slow drag right turns back")
        // Flick: short but fast.
        point(0.8).press(forDuration: 0.05, thenDragTo: point(0.55), withVelocity: .fast, thenHoldForDuration: 0)
        sleep(2); XCTAssertEqual(page, "2", "fast short flick turns")
        // Mid-drag hold: the page is offset under the finger; release past half turns.
        holdMidDrag("single-mid", from: 0.9, to: 0.3)
        XCTAssertEqual(page, "3")
        // First page: nothing before it, so a drag right springs back.
        slowDrag(0.15, 0.8); slowDrag(0.15, 0.8); XCTAssertEqual(page, "1")
        slowDrag(0.15, 0.85); XCTAssertEqual(page, "1", "no page before the first: springs back")

        // Right to left spreads: forward is a drag to the right.
        pick("雙頁右至左"); XCTAssertEqual(page, "1"); shot("03-rtl-cover")
        slowDrag(0.1, 0.75); XCTAssertEqual(page, "2", "RTL: slow drag right turns forward"); shot("04-rtl-p2-3")
        slowDrag(0.1, 0.35); XCTAssertEqual(page, "2", "RTL: short drag springs back")
        holdMidDrag("rtl-mid", from: 0.1, to: 0.75)
        XCTAssertEqual(page, "4")
        slowDrag(0.9, 0.25); XCTAssertEqual(page, "2", "RTL: drag left turns back")
    }
}
#endif
