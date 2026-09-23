//
//  PDFViewerUITests.swift
//  PDFViewerUITests
//
//  Created by steveyeh on 2025/7/10.
//

import XCTest

final class PDFViewerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsOpenFileAction() throws {
        let app = XCUIApplication()
        app.launch()

        let localizedButton = app.buttons["開啟檔案"]
        let englishButton = app.buttons["Open File"]
        XCTAssertTrue(
            localizedButton.waitForExistence(timeout: 5) || englishButton.waitForExistence(timeout: 1),
            "The empty reader should expose an Open File action."
        )
    }

    @MainActor
    func testMainWindowCanBeReopened() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 5) { app.windows.count == 0 })

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}
