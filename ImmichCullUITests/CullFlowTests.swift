import XCTest

/// End-to-end flow against the mock Immich server (scratchpad/mock_immich.py on 127.0.0.1:2283).
final class CullFlowTests: XCTestCase {
    @MainActor
    func testConnectSelectAlbumAndCull() throws {
        resetMockServer()
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
        // Tapping the album opens its full-screen stream; "Cull" starts the deck.
        forceTap(testAlbumRow)
        attachScreenshot(of: app, named: "after-album-tap")
        XCTAssertTrue(app.buttons.matching(identifier: "gridCell").firstMatch.waitForExistence(timeout: 15),
                      "Album stream should load its assets")
        forceTap(app.buttons["albumStreamCull"])

        XCTAssertTrue(app.staticTexts["1 of 5"].waitForExistence(timeout: 15), "First card should load")

        app.swipeUp() // trash
        XCTAssertTrue(app.staticTexts["2 of 5"].waitForExistence(timeout: 5))
        app.swipeLeft() // keep
        XCTAssertTrue(app.staticTexts["3 of 5"].waitForExistence(timeout: 5))
        app.swipeDown() // add to album
        XCTAssertTrue(app.staticTexts["4 of 5"].waitForExistence(timeout: 5))

        // Going back must not undo the album add: the badge has to survive it.
        // Before, stepping back reverted the action and the badge vanished.
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["3 of 5"].waitForExistence(timeout: 5))
        XCTAssertTrue(inAlbumBadge(in: app).waitForExistence(timeout: 5),
                      "Stepping back should leave the photo in the album")

        // Swiping down again on a photo that is already in the album takes it
        // back out, rather than adding it a second time.
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["4 of 5"].waitForExistence(timeout: 5))
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["3 of 5"].waitForExistence(timeout: 5))
        // Only ever one photo touched the album, so no badge anywhere proves
        // the removal landed rather than a second add.
        XCTAssertFalse(inAlbumBadge(in: app).exists,
                       "Swiping down again should have removed it from the album")

        // Put it back so the counts below still line up.
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["4 of 5"].waitForExistence(timeout: 5))

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["5 of 5"].waitForExistence(timeout: 5))
        app.swipeLeft()

        // Summary screen after the last card. The grid was dismissed when culling
        // started, so the deck sits directly over Home — its "Done" is unambiguous.
        XCTAssertTrue(app.staticTexts["All done"].waitForExistence(timeout: 5))
        forceTap(app.buttons["Done"]) // deck summary → Home
        XCTAssertTrue(testAlbumRow.waitForExistence(timeout: 5), "Should return to the album list")
    }

    /// Undo has to go inert right after a step back. The record it would have
    /// undone is gone, so the stack's top refers to an earlier, off-screen
    /// photo — leaving it live would revert something you can't see.
    @MainActor
    func testUndoIsDisabledAfterSteppingBack() throws {
        resetMockServer()
        let app = launchConnectedApp()

        let testAlbumRow = albumRow(named: "Test Album", in: app)
        XCTAssertTrue(testAlbumRow.waitForExistence(timeout: 15), "Album list should appear")
        scrollUntilHittable(testAlbumRow, in: app)
        forceTap(testAlbumRow)
        XCTAssertTrue(app.buttons.matching(identifier: "gridCell").firstMatch.waitForExistence(timeout: 15),
                      "Album stream should load its assets")
        forceTap(app.buttons["albumStreamCull"])
        XCTAssertTrue(app.staticTexts["1 of 5"].waitForExistence(timeout: 15), "First card should load")

        let undo = app.buttons["Undo"]
        XCTAssertFalse(undo.isEnabled, "Nothing has been done yet")

        app.swipeDown() // add to album
        XCTAssertTrue(app.staticTexts["2 of 5"].waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled, "The album add should be undoable")

        app.swipeRight() // step back
        XCTAssertTrue(app.staticTexts["1 of 5"].waitForExistence(timeout: 5))
        XCTAssertFalse(undo.isEnabled, "Undo has no target after stepping back")

        app.swipeDown() // acting again gives it one
        XCTAssertTrue(app.staticTexts["2 of 5"].waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled, "Acting again should revive Undo")
    }

    // MARK: Helpers

    /// Rows are matched on the combined button label; the inner StaticText
    /// isn't hit-testable.
    @MainActor
    private func albumRow(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    @MainActor
    private func inAlbumBadge(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'In album'"))
            .firstMatch
    }

    /// Connects to the mock and lands on the album list, absorbing the system
    /// prompts that can otherwise swallow taps.
    @MainActor
    private func launchConnectedApp() -> XCUIApplication {
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
        return app
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
