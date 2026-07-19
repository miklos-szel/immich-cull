import XCTest

/// End-to-end flow against the mock Immich server (scratchpad/mock_immich.py on 127.0.0.1:2283).
final class CullFlowTests: XCTestCase {
    @MainActor
    func testConnectSelectAlbumAndCull() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset"]
        // Deterministic mock ID (uuid5 of "immich-mock-album-keepers"); avoids
        // driving the Settings sheet, whose toolbar button XCUITest cannot tap on iOS 26.
        app.launchEnvironment = [
            "UITEST_ALBUM_ID": "7122f33f-bc44-5ca3-95d4-19c7419cfee9",
            "UITEST_ALBUM_NAME": "Keepers",
        ]
        app.launch()

        // The discovery scan triggers the Local Network permission prompt (a
        // SpringBoard alert invisible to app queries) — approve it if it appears.
        allowLocalNetworkPrompt(timeout: 5)

        // Connect to the mock server.
        let urlField = app.textFields["serverURLField"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 10), "Setup screen should appear")
        urlField.tap()
        urlField.typeText("http://127.0.0.1:2283")
        let keyField = app.textFields["apiKeyField"]
        keyField.tap()
        keyField.typeText("test-key")
        app.buttons["Connect"].tap()

        // Dismiss the system password-save prompt if it still shows up.
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) {
            notNow.tap()
        }
        // The local network prompt can also surface late, swallowing all taps.
        allowLocalNetworkPrompt(timeout: 3)

        // Home: albums loaded from the mock. Tap the row button, not its inner static text.
        let testAlbumRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Test Album'")).firstMatch
        XCTAssertTrue(testAlbumRow.waitForExistence(timeout: 10), "Album list should appear after connecting")

        // The Save Password dialog can surface late and swallow taps; clear any straggler.
        for _ in 0..<3 where notNow.exists {
            forceTap(notNow)
            _ = testAlbumRow.waitForExistence(timeout: 1)
        }

        // Start culling the 5-asset test album (destination album preset via launch environment).
        // The Stats and Cleanup sections sit above the albums, so scroll the row into view first.
        scrollUntilHittable(testAlbumRow, in: app)
        attachScreenshot(of: app, named: "before-album-tap")
        forceTap(testAlbumRow)
        attachScreenshot(of: app, named: "after-album-tap")
        forceTap(app.buttons["Cull 1 Album"])

        XCTAssertTrue(app.staticTexts["1 of 5"].waitForExistence(timeout: 15), "First card should load")

        app.swipeUp() // trash
        XCTAssertTrue(app.staticTexts["2 of 5"].waitForExistence(timeout: 5))
        app.swipeLeft() // keep
        XCTAssertTrue(app.staticTexts["3 of 5"].waitForExistence(timeout: 5))
        app.swipeDown() // add to album
        XCTAssertTrue(app.staticTexts["4 of 5"].waitForExistence(timeout: 5))

        // Undo the album add via right swipe, then redo it.
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["3 of 5"].waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["4 of 5"].waitForExistence(timeout: 5))

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["5 of 5"].waitForExistence(timeout: 5))
        app.swipeLeft()

        // Summary screen after the last card.
        XCTAssertTrue(app.staticTexts["All done"].waitForExistence(timeout: 5))
        forceTap(app.buttons["Done"])
        XCTAssertTrue(testAlbumRow.waitForExistence(timeout: 5), "Should return to the album list")
    }

    /// Approves the Local Network system alert if it is on screen.
    @MainActor
    private func allowLocalNetworkPrompt(timeout: TimeInterval) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: timeout) {
            allow.tap()
        }
    }

}
