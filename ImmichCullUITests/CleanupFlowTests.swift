import XCTest

/// Drives the four cleanup finders against the mock server on 127.0.0.1:2283.
final class CleanupFlowTests: XCTestCase {
    @MainActor
    private func launchConnectedApp() -> XCUIApplication {
        resetMockServer()
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset"]
        app.launchEnvironment = [
            "UITEST_SERVER_URL": "http://127.0.0.1:2283",
            "UITEST_API_KEY": "test-key",
            "UITEST_DISABLE_PHOTO_DELETE": "1",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func trashButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Move'")).firstMatch
    }

    @MainActor
    func testBlurryScanFindsCandidates() throws {
        try XCTSkipIf(true, "Blurry finder temporarily hidden from Home; code path retained.")
        let app = launchConnectedApp()
        forceTap(app.buttons["Find Blurry Photos"])
        // Solid-color mock thumbnails all score 0, so everything is preselected.
        let button = trashButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 60), "Scan should finish and show the trash button")
        XCTAssertTrue(button.label.contains("Move"), "Trash button should reflect selection")
    }

    @MainActor
    func testDuplicatesFlow() throws {
        try XCTSkipIf(true, "Duplicates finder temporarily hidden from Home; code path retained.")
        let app = launchConnectedApp()
        forceTap(app.buttons["Find Duplicates"])

        let button = trashButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 15), "Duplicate group should load")
        XCTAssertEqual(button.label, "Move 1 to Trash", "Non-suggested copy should be preselected")
        forceTap(button)
        let confirm = app.buttons["Move to Trash"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Confirmation dialog should appear")
        forceTap(confirm)

        let empty = app.staticTexts["No duplicates"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "Group should disappear after trashing its extra copy")
    }

    @MainActor
    func testScreenshotsFinder() throws {
        try XCTSkipIf(true, "Screenshots finder temporarily hidden from Home; code path retained.")
        let app = launchConnectedApp()
        forceTap(app.buttons["Find Screenshots"])

        let button = trashButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 15), "Screenshot results should load")
        XCTAssertEqual(button.label, "Move 1 to Trash", "The single PNG screenshot should be found and preselected")
    }

    @MainActor
    func testTrashBinRestore() throws {
        let app = launchConnectedApp()
        forceTap(app.buttons["Cull Entire Roll"])

        let progress = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 of'")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 15), "First card should load")
        app.swipeUp() // trash the current asset
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '2 of'")).firstMatch
            .waitForExistence(timeout: 5), "Should advance after trashing")

        let trashButton = app.buttons["trashBinButton"]
        waitForLabel(trashButton, matching: "label == 'Trash bin, 1 item'")

        forceTap(trashButton)
        let restore = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Restore'")).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 10), "Trash bin should show the trashed asset")
        forceTap(app.buttons["Select All"])
        forceTap(restore)
        XCTAssertTrue(app.staticTexts["Trash is empty"].waitForExistence(timeout: 10),
                      "Bin should be empty after restoring")

        // Restoring must also clear the badge and the session's trash tally.
        forceTap(app.buttons["Done"])
        waitForLabel(trashButton, matching: "label == 'Trash bin'")
    }

    @MainActor
    func testTrashBinPermanentDelete() throws {
        let app = launchConnectedApp()
        forceTap(app.buttons["Cull Entire Roll"])

        let progress = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 of'")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 15), "First card should load")
        app.swipeUp() // trash the current asset
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '2 of'")).firstMatch
            .waitForExistence(timeout: 5), "Should advance after trashing")

        // The badge counts the one asset now sitting in the Immich trash.
        let badgedTrashButton = app.buttons["trashBinButton"]
        waitForLabel(badgedTrashButton, matching: "label == 'Trash bin, 1 item'")

        forceTap(badgedTrashButton)
        XCTAssertTrue(app.buttons["Select All"].waitForExistence(timeout: 10), "Trash bin should load")
        forceTap(app.buttons["Select All"])
        forceTap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete'")).firstMatch)
        let confirm = app.buttons["Delete Permanently"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Confirmation dialog should appear")
        forceTap(confirm)
        XCTAssertTrue(app.staticTexts["Trash is empty"].waitForExistence(timeout: 10),
                      "Bin should be empty after permanent delete")

        // Emptying the bin must clear the badge back to zero.
        forceTap(app.buttons["Done"])
        waitForLabel(badgedTrashButton, matching: "label == 'Trash bin'")
    }

    /// Album counts must reflect what culling did, without a manual refresh.
    @MainActor
    func testAlbumCountRefreshesAfterCulling() throws {
        let app = launchConnectedApp()

        let testAlbum = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Test Album'")).firstMatch
        scrollUntilHittable(testAlbum, in: app)
        XCTAssertTrue(testAlbum.waitForExistence(timeout: 15), "Album list should load")
        XCTAssertEqual(testAlbum.label, "Test Album, 5 items", "Fixture starts with five")

        // Cull just that album and bin one photo.
        forceTap(testAlbum)
        forceTap(app.buttons["Cull 1 Album"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 of'")).firstMatch
            .waitForExistence(timeout: 15), "First card should load")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '2 of'")).firstMatch
            .waitForExistence(timeout: 10), "Should advance after trashing")

        // Returning to the main menu must show the new count.
        forceTap(app.buttons["Close"])
        let updated = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Test Album'")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 15), "Back on the album list")
        waitForLabel(updated, matching: "label == 'Test Album, 4 items'")

        // The album must still be the (single) selection. Selection used to be
        // keyed by value, so a changed count stranded the old entry and the
        // start button reported two albums with one ticked.
        XCTAssertTrue(updated.isSelected, "Selection should survive the count changing")
        XCTAssertTrue(app.buttons["Cull 1 Album"].waitForExistence(timeout: 10),
                      "Should still be culling exactly one album")
    }

    /// The album title opens a grid: tapping a photo continues from it, and
    /// selection mode trashes several at once.
    @MainActor
    func testGridJumpAndBulkTrash() throws {
        let app = launchConnectedApp()
        forceTap(app.buttons["Cull Entire Roll"])

        let firstCard = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 of'")).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 15), "First card should load")

        // Jump: pick the third thumbnail and continue from it.
        forceTap(app.buttons["albumTitleButton"])
        let cells = app.scrollViews.buttons
        XCTAssertTrue(cells.element(boundBy: 2).waitForExistence(timeout: 10), "Grid should list the queue")
        forceTap(cells.element(boundBy: 2))
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10),
                      "Jumping keeps the progress at the first unreviewed card")

        // Bulk trash: select two photos from the grid and bin them.
        forceTap(app.buttons["albumTitleButton"])
        forceTap(app.buttons["Select"])
        forceTap(cells.element(boundBy: 0))
        forceTap(cells.element(boundBy: 1))
        let trash = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Move 2'")).firstMatch
        XCTAssertTrue(trash.waitForExistence(timeout: 5), "Two photos should be selected")
        forceTap(trash)
        let confirm = app.buttons["Move to Trash"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Confirmation should appear")
        forceTap(confirm)

        forceTap(app.buttons["Done"])
        // Both are now in the Immich bin.
        waitForLabel(app.buttons["trashBinButton"], matching: "label == 'Trash bin, 2 items'")
    }

    @MainActor
    func testReceiptsFinder() throws {
        try XCTSkipIf(true, "Receipts finder temporarily hidden from Home; code path retained.")
        let app = launchConnectedApp()
        forceTap(app.buttons["Find Receipts & Bills"])

        let button = trashButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 15), "Smart search results should load")
        XCTAssertEqual(button.label, "Move 0 to Trash", "Receipt candidates should not be preselected")
    }
}
