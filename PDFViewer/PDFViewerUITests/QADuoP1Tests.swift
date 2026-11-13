#if os(iOS)
import XCTest
final class QADuoP1Tests: XCTestCase {
    var env: [String: String] { ProcessInfo.processInfo.environment }
    var out: String { env["QA_OUT"] ?? "/Users/steveyeh/Projects/PDFviewer/duo-tools/shots/qa" }
    var tag: String { env["QA_TAG"] ?? "x" }
    var app: XCUIApplication!
    func shot(_ n: String) {
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(tag)-\(n).png"))
    }
    func write(_ s: String) {
        let p = "\(out)/\(tag)-frames.txt"
        if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(s.data(using: .utf8)!); h.closeFile() } else { try? s.write(toFile: p, atomically: true, encoding: .utf8) }
    }
    var page: String { let f = app.textFields.firstMatch; return f.exists ? (f.value as? String ?? "?") : "nofield" }
    var mode: String {
        for l in ["單頁", "雙頁左至右", "雙頁右至左"] { let b = app.buttons[l].firstMatch; if b.exists && b.isSelected { return l } }
        let m = app.buttons["閱讀模式"].firstMatch; return m.exists ? "menu:\(m.value ?? "")" : "?"
    }
    func log(_ n: String, full: Bool = true) {
        var s = "== \(tag) \(n) orient=\(XCUIDevice.shared.orientation.rawValue) win=\(app.windows.firstMatch.frame) page=\(page) mode=\(mode)\n"
        for nb in app.navigationBars.allElementsBoundByIndex where nb.exists { s += "NAVBAR '\(nb.identifier)' \(nb.frame)\n" }
        if full {
            for q in [app.buttons, app.textFields, app.sliders, app.staticTexts] {
                for e in q.allElementsBoundByIndex where e.exists { s += "\(e.elementType.rawValue) '\(e.label)' id='\(e.identifier)' val='\(e.value ?? "")' \(e.frame) hit=\(e.isHittable)\n" }
            }
        }
        write(s)
    }
    /// Sample PDF the seeded recents entry points at. Override with
    /// `TEST_RUNNER_QA_SAMPLE_PDF=/path/to.pdf xcodebuild test ...`.
    var samplePath: String { env["QA_SAMPLE_PDF"] ?? "/Users/steveyeh/Projects/PDFviewer/duo-tools/sample.pdf" }
    /// `-recentPDFFiles_v2` launch argument: the recents JSON as an NSData plist literal (`<hex>`).
    func recentsArgument() throws -> String {
        XCTAssertTrue(FileManager.default.fileExists(atPath: samplePath), "sample PDF missing at \(samplePath)")
        let entry: [String: Any] = [
            "id": "qa-sample", "path": samplePath, "name": (samplePath as NSString).lastPathComponent,
            "lastOpened": 815000000.0, "currentPage": 1, "totalPages": 6, "readingMode": "singlePage",
            "isContinuous": false, "appearance": "automatic", "zoomLevel": "fitPage",
        ]
        let json = try JSONSerialization.data(withJSONObject: [entry], options: [.sortedKeys])
        return "<" + json.map { String(format: "%02x", $0) }.joined() + ">"
    }
    /// Center of the PDF area: between the nav bar bottom and the top of the lowest control row, so the tap never lands on controls.
    func pdfCenter() -> XCUICoordinate {
        let win = app.windows.firstMatch.frame
        var top = win.minY
        for nb in app.navigationBars.allElementsBoundByIndex where nb.exists { top = max(top, nb.frame.maxY) }
        var bottom = win.maxY
        for q in [app.buttons, app.sliders, app.textFields] {
            for e in q.allElementsBoundByIndex where e.exists && e.frame.minY > win.midY { bottom = min(bottom, e.frame.minY) }
        }
        let y = (top + bottom) / 2
        write("pdfCenter top=\(top) bottom=\(bottom) tapY=\(y) win=\(win)\n")
        return app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: win.midX - win.minX, dy: y - win.minY))
    }
    /// `TEST_RUNNER_QA_FOLD=455,495`: the fold band (pt, landscape) that reader panels must keep clear.
    var foldBand: ClosedRange<CGFloat>? {
        guard let v = env["QA_FOLD"]?.split(separator: ",").compactMap({ Double($0) }), v.count == 2 else { return nil }
        return CGFloat(v[0])...CGFloat(v[1])
    }
    func onBand(_ f: CGRect, _ band: ClosedRange<CGFloat>) -> Bool { f.width > 0 && f.height > 0 && f.minX < band.upperBound && f.maxX > band.lowerBound }
    /// Fold display: the search / browse panel lies wholly right of the fold and nothing tappable sits on the band.
    func checkFoldPanel(_ band: ClosedRange<CGFloat>, _ key: String) {
        let panel = app.otherElements["FoldReaderPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 3), "\(key): no FoldReaderPanel on the fold display")
        guard panel.exists else { return }
        let pf = panel.frame
        write("FOLDPANEL \(key) \(pf)\n")
        XCTAssertGreaterThanOrEqual(pf.minX, band.upperBound, "\(key): panel reaches the fold \(pf)")
        // The band check below only counts hittable elements, so the panel's own controls must be hittable.
        let done = panel.buttons["完成"].firstMatch
        XCTAssertTrue(done.exists && done.isHittable, "\(key): panel 完成 not hittable")
        var hits: [String] = []
        for e in panel.descendants(matching: .any).allElementsBoundByIndex.prefix(200) where e.exists && onBand(e.frame, band) && e.isHittable {
            hits.append("panel \(e.elementType.rawValue) '\(e.label)' \(e.frame)")
        }
        for q in [app.buttons, app.textFields, app.searchFields, app.segmentedControls, app.cells] {
            for e in q.allElementsBoundByIndex where e.exists && onBand(e.frame, band) && e.isHittable {
                hits.append("app \(e.elementType.rawValue) '\(e.label)' \(e.frame)")
            }
        }
        write("FOLDBAND \(key) hittable=\(hits)\n")
        XCTAssertTrue(hits.isEmpty, "\(key): hittable on fold band \(band): \(hits)")
    }
    /// `TEST_RUNNER_QA_SHEET_CENTER=1` (iPad / iPhone without a fold): the sheet is the centered system sheet.
    func checkCenteredSheet(_ key: String) {
        let nb = app.navigationBars[key == "search" ? "搜尋" : "瀏覽"].firstMatch
        XCTAssertTrue(nb.waitForExistence(timeout: 3), "\(key): sheet nav bar missing")
        let w = app.windows.firstMatch.frame
        write("CENTER \(key) sheet=\(nb.frame) windowMidX=\(w.midX)\n")
        XCTAssertEqual(nb.frame.midX, w.midX, accuracy: 1, "\(key): sheet not centered \(nb.frame)")
    }
    @MainActor func testP1Flow() throws {
        app = XCUIApplication()
        app.launchArguments = ["-recentPDFFiles_v2", try recentsArgument()]
        if let cs = env["QA_CS"] { app.launchArguments += ["-UIPreferredContentSizeCategoryName", cs] }
        app.launch()
        let orient: UIDeviceOrientation = env["QA_START"] == "land" ? .landscapeLeft : .portrait
        XCUIDevice.shared.orientation = orient
        sleep(2); shot("01-launch"); log("launch")
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'sample'")).firstMatch
        if !row.isHittable { XCUIDevice.shared.orientation = .portrait; sleep(1) }
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap(); sleep(3)
        shot("02-reader"); log("reader")
        // go to page 3 via field
        let f = app.textFields.firstMatch
        _ = f
        let pdfArea = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        for _ in 0..<2 { pdfArea.press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.45))); sleep(2) }
        shot("03-page3"); log("page3", full: false)
        for (o, n) in [(UIDeviceOrientation.landscapeLeft, "landL"), (.portrait, "portrait"), (.landscapeRight, "landR")] {
            XCUIDevice.shared.orientation = o; sleep(3); shot("04-\(n)"); log("rot-\(n)")
        }
        if env["QA_SPLIT"] != nil {
            XCUIDevice.shared.orientation = .landscapeLeft; sleep(3)
            let toggle = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'sidebar' OR label CONTAINS[c] 'sidebar' OR label CONTAINS '側邊欄'")).firstMatch
            for i in 1...2 {
                shot("07-split-before-toggle\(i)"); log("split-before-toggle\(i) toggleExists=\(toggle.exists) '\(toggle.label)'", full: i == 1)
                if toggle.exists { toggle.tap(); sleep(3) }
                shot("07-split-after-toggle\(i)"); log("split-after-toggle\(i)", full: false)
                let t2 = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'sidebar' OR label CONTAINS[c] 'sidebar' OR label CONTAINS '側邊欄'")).firstMatch
                if t2.exists && i == 1 { write("toggle2 '\(t2.label)' id='\(t2.identifier)'\n") }
                if !t2.exists && i == 1 { app.swipeRight(); sleep(2) }
            }
            // Manual pick wins: choose single page while spread is allowed.
            let single = app.buttons["單頁"].firstMatch
            if single.exists && single.isHittable { single.tap(); sleep(2); if toggle.exists { toggle.tap(); sleep(3) }; shot("08-manual-single"); log("manual-single then toggle", full: false) }
        }
        XCUIDevice.shared.orientation = .landscapeLeft; sleep(2)
        pdfCenter().tap(); sleep(2)
        shot("05-tap-hide"); log("tap-hide navbars=\(app.navigationBars.count) exit=\(app.buttons["退出全螢幕閱讀"].exists)", full: false)
        pdfCenter().tap(); sleep(2)
        shot("06-tap-show"); log("tap-show navbars=\(app.navigationBars.count) fs=\(app.buttons["全螢幕閱讀"].exists)", full: false)
        pdfCenter().doubleTap(); sleep(2)
        log("after-doubletap navbars=\(app.navigationBars.count)", full: false)
        XCUIDevice.shared.orientation = .portrait; sleep(2)
        if env["QA_SHEETS"] != nil {
            for (o, n) in [(UIDeviceOrientation.portrait, "p"), (.landscapeLeft, "l")] {
                XCUIDevice.shared.orientation = o; sleep(2)
                for (label, key) in [("搜尋", "search"), ("縮圖與目錄", "browse")] {
                    let b = app.buttons[label].firstMatch
                    guard b.waitForExistence(timeout: 3), b.isHittable else { write("sheet \(key)-\(n) button missing\n"); continue }
                    b.tap(); sleep(2)
                    shot("09-sheet-\(key)-\(n)"); log("sheet-\(key)-\(n)")
                    if n == "l", let band = foldBand { checkFoldPanel(band, key) }
                    if n == "l", env["QA_SHEET_CENTER"] != nil { checkCenteredSheet(key) }
                    let done = app.buttons.matching(NSPredicate(format: "label IN {'完成', 'Done', '關閉', 'Close', '取消', 'Cancel'}")).firstMatch
                    if done.exists && done.isHittable { done.tap() } else { app.swipeDown(velocity: .fast) }
                    sleep(2)
                }
            }
            XCUIDevice.shared.orientation = .portrait; sleep(1)
        }
    }
}
#endif
