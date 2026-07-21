import XCTest

/// Captures the README screenshots by walking the app against the mock server.
///
/// Skipped unless `CAPTURE_SCREENSHOTS` is set, so it stays out of the normal
/// suite — it asserts almost nothing and exists only for its attachments.
/// Run it via `scripts/capture-screenshots.sh`, which also extracts the images
/// out of the result bundle.
///
/// It runs against the mock deliberately: the mock's images are generated, so
/// no photo from a real library can end up in the repository.
final class ScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureReadmeScreenshots() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CAPTURE_SCREENSHOTS"] == nil,
                      "Set CAPTURE_SCREENSHOTS to capture README images")
        resetMockServer()

        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset"]
        app.launchEnvironment = [
            "UITEST_ALBUM_ID": "7122f33f-bc44-5ca3-95d4-19c7419cfee9",
            "UITEST_ALBUM_NAME": "Keepers",
            "UITEST_SERVER_URL": "http://127.0.0.1:2283",
            "UITEST_API_KEY": "test-key",
        ]
        app.launch()
        allowLocalNetworkPrompt(timeout: 5)

        // 1. Album list.
        let testAlbumRow = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH 'Test Album'")).firstMatch
        XCTAssertTrue(testAlbumRow.waitForExistence(timeout: 15), "Album list should appear")
        scrollUntilHittable(testAlbumRow, in: app)
        capture(app, named: "01-albums")
        // Tapping the album opens its stream; "Cull" starts the deck.
        forceTap(testAlbumRow)

        // 2. The deck, with a photo already favourited and filed so the badges
        //    are visible — the screenshot should show the feature, not an
        //    untouched library.
        XCTAssertTrue(app.buttons.matching(identifier: "gridCell").firstMatch.waitForExistence(timeout: 15),
                      "Album stream should load")
        forceTap(app.buttons["albumStreamCull"])
        XCTAssertTrue(app.staticTexts["1 of 5"].waitForExistence(timeout: 15), "First card should load")
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["2 of 5"].waitForExistence(timeout: 5))
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["1 of 5"].waitForExistence(timeout: 5))
        capture(app, named: "02-deck")

        // 3. The paged grid.
        forceTap(app.buttons["albumTitleButton"])
        XCTAssertTrue(app.buttons.matching(identifier: "gridCell").element(boundBy: 2)
            .waitForExistence(timeout: 10), "Grid should list the queue")
        capture(app, named: "03-grid")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func allowLocalNetworkPrompt(timeout: TimeInterval) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: timeout) {
            allow.tap()
        }
    }
}
