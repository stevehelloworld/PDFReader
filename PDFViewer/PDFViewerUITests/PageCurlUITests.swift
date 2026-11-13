#if os(iOS)
import XCTest

/// Page-curl reader: drag turns, cancelled drags, RTL spreads, pinch hand-off to PDFView.
/// Env (via TEST_RUNNER_ prefix): QA_SAMPLE_PDF (6-page fixture), QA_OUT (screenshots),
/// QA_MARKERS (host watcher dir: a file per mid-curl hold so the host can screenshot it).
final class PageCurlUITests: XCTestCase {
    var env: [String: String] { ProcessInfo.processInfo.environment }
    var out: String { env["QA_OUT"] ?? "/tmp/comicp1-curl" }
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
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/curl-\(name).png"))
    }

    var page: String { app.textFields.firstMatch.value as? String ?? "?" }
    var reader: XCUIElement { app.descendants(matching: .any)["PageCurlReader"] }

    /// Point inside the reader (not the window: on iPad the library column sits on the left).
    func point(_ x: CGFloat, _ y: CGFloat = 0.42) -> XCUICoordinate {
        let target = reader.exists ? reader : app.windows.firstMatch
        return target.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    func drag(_ from: CGFloat, _ to: CGFloat, velocity: XCUIGestureVelocity = .fast) {
        point(from).press(forDuration: 0.05, thenDragTo: point(to), withVelocity: velocity, thenHoldForDuration: 0)
        sleep(2)
    }

    /// Drags to the middle and holds, so the host watcher can capture the curl half-way.
    func holdMidCurl(_ name: String, from: CGFloat, to: CGFloat) {
        if let dir = env["QA_MARKERS"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? name.write(toFile: "\(dir)/\(name)", atomically: true, encoding: .utf8)
        }
        point(from).press(forDuration: 0.2, thenDragTo: point(to), withVelocity: .slow, thenHoldForDuration: 3.5)
        sleep(2)
    }

    func pick(_ mode: String) {
        let b = app.buttons[mode].firstMatch
        if b.exists && b.isHittable { b.tap() } else {
            app.buttons["閱讀設定"].firstMatch.tap(); sleep(1); app.buttons[mode].firstMatch.tap()
        }
        sleep(2)
    }

    @MainActor func testPageCurlFlow() throws {
        app = XCUIApplication()
        app.launchArguments = ["-recentPDFFiles_v2", try recentsArgument()]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'sample'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap(); sleep(3)
        XCTAssertTrue(reader.waitForExistence(timeout: 5), "curl reader not shown at fit-page")
        XCTAssertEqual(page, "1"); shot("01-single-p1")

        // Single page, forward / back.
        drag(0.9, 0.1); XCTAssertEqual(page, "2", "drag left should turn forward"); shot("02-single-p2")
        drag(0.1, 0.9); XCTAssertEqual(page, "1", "drag right should turn back")
        // Cancelled: short slow drag springs back.
        point(0.92).press(forDuration: 0.2, thenDragTo: point(0.8), withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(2); XCTAssertEqual(page, "1", "short drag must cancel")
        holdMidCurl("single-mid", from: 0.92, to: 0.45)
        XCTAssertEqual(page, "2", "released past the middle completes the turn")
        drag(0.1, 0.9); XCTAssertEqual(page, "1")

        // Two pages, left to right: cover alone, then 2-3.
        pick("雙頁左至右"); XCTAssertTrue(reader.exists); XCTAssertEqual(page, "1"); shot("03-ltr-cover")
        drag(0.9, 0.1); XCTAssertEqual(page, "2"); shot("04-ltr-p2-3")
        holdMidCurl("ltr-mid", from: 0.95, to: 0.3)
        XCTAssertEqual(page, "4")

        // Two pages, right to left: forward is a drag to the right.
        pick("雙頁右至左"); XCTAssertEqual(page, "4"); shot("05-rtl-p4-5")
        drag(0.1, 0.9); XCTAssertEqual(page, "6", "RTL: drag right turns forward"); shot("06-rtl-p6")
        drag(0.9, 0.1); XCTAssertEqual(page, "4", "RTL: drag left turns back")
        holdMidCurl("rtl-mid", from: 0.05, to: 0.7)
        XCTAssertEqual(page, "6")

        // Scrubber jump keeps working (no curl for non-adjacent jumps).
        let slider = app.sliders.firstMatch
        if slider.exists { slider.adjust(toNormalizedSliderPosition: 0.4); sleep(2) }
        XCTAssertEqual(page, "3"); shot("07-rtl-jump-p3")

        // Pinch out hands over to PDFView at a zoom preset; fit-page brings the curl back.
        reader.pinch(withScale: 2.5, velocity: 2); sleep(2)
        XCTAssertFalse(reader.exists, "zoomed reading should use PDFView"); shot("08-zoomed-pdfview")
        XCTAssertEqual(page, "3")
        app.buttons["閱讀設定"].firstMatch.tap(); sleep(1)
        app.buttons["適應頁面"].firstMatch.tap(); sleep(2)
        XCTAssertTrue(reader.exists, "fit page returns to curl"); XCTAssertEqual(page, "3")
    }
}
#endif
