import XCTest

/// End-to-end coverage against a real Immich server. Runs only when
/// REAL_SERVER_URL / REAL_SERVER_API_KEY are set, so the normal suite is
/// unaffected.
///
/// Every mutation here is reversed before the test ends: a trashed asset is
/// restored from the bin, and a tagged asset is un-tagged via "previous image".
/// Nothing is ever deleted permanently.
final class RealServerSmokeTests: XCTestCase {
    @MainActor
    private func launchConnectedApp() throws -> XCUIApplication {
        let environment = ProcessInfo.processInfo.environment
        guard let serverURL = environment["REAL_SERVER_URL"],
              let apiKey = environment["REAL_SERVER_API_KEY"] else {
            throw XCTSkip("REAL_SERVER_URL / REAL_SERVER_API_KEY not set")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset"]
        app.launchEnvironment = [
            "UITEST_SERVER_URL": serverURL,
            "UITEST_API_KEY": apiKey,
            // Keep the iOS Photos permission prompt out of the run.
            "UITEST_DISABLE_PHOTO_DELETE": "1",
        ]
        app.launch()
        return app
    }

    /// Home screen: albums load from the real server, including non-ASCII names.
    @MainActor
    func testHomeListsRealAlbums() throws {
        let app = try launchConnectedApp()

        let entireRoll = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Entire Roll'")).firstMatch
        XCTAssertTrue(entireRoll.waitForExistence(timeout: 20), "Home should list the cull scope")
        attachScreenshot(of: app, named: "real-home")

        let albumRows = app.buttons.matching(NSPredicate(format: "label CONTAINS ' assets' OR label CONTAINS ' items'"))
        XCTAssertGreaterThan(albumRows.count, 0, "Real server albums should be listed")
    }

    /// Full round trip: trash a real asset, confirm the badge and bin update,
    /// then restore it so the server is left as we found it.
    @MainActor
    func testTrashAndRestoreRoundTrip() throws {
        let app = try launchConnectedApp()

        let cullAll = app.buttons["Cull Entire Roll"]
        XCTAssertTrue(cullAll.waitForExistence(timeout: 20), "Should land on Home when preconfigured")
        forceTap(cullAll)

        let firstCard = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 of'")).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 60), "First card should load from the real server")
        sleep(3) // let the image render for the screenshot
        attachScreenshot(of: app, named: "real-first-card")

        // Baseline trash count from the badge, e.g. "Trash bin, 20 items".
        // It is fetched from the server concurrently with the library load, so
        // wait for it to settle rather than reading a half-loaded value.
        let trashButton = app.buttons["trashBinButton"]
        XCTAssertTrue(trashButton.waitForExistence(timeout: 20))
        let before = settledBadgeCount(trashButton)

        // Swipe up = trash.
        app.swipeUp()
        let secondCard = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '2 of'")).firstMatch
        XCTAssertTrue(secondCard.waitForExistence(timeout: 20), "Should advance after trashing")

        // The badge must grow. Asserting the delta rather than an absolute
        // number keeps this stable regardless of what's already in the bin.
        let afterTrash = waitForBadge(trashButton, satisfying: { $0 > before })
        XCTAssertGreaterThan(afterTrash, before, "Trashing should increase the badge")
        attachScreenshot(of: app, named: "real-after-trash")

        // The bin lists real trashed assets (read-only check — we must not
        // restore anything the user binned deliberately).
        forceTap(trashButton)
        let restore = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Restore'")).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 30), "Bin should list trashed assets")
        attachScreenshot(of: app, named: "real-trash-bin")
        forceTap(app.buttons["Done"])

        // Undo reverses exactly the asset this test trashed, leaving every
        // other bin item untouched.
        forceTap(app.buttons["Undo"])
        XCTAssertTrue(firstCard.waitForExistence(timeout: 20), "Undo should step back to the trashed image")
        let afterRestore = waitForBadge(trashButton, satisfying: { $0 < afterTrash })
        XCTAssertLessThan(afterRestore, afterTrash, "Restoring should shrink the badge")
    }

    /// Polls the badge until it satisfies `predicate`, returning the last value.
    @MainActor
    private func waitForBadge(_ element: XCUIElement,
                              satisfying predicate: (Int) -> Bool,
                              timeout: TimeInterval = 30) -> Int {
        var value = Self.badgeCount(element.label)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            value = Self.badgeCount(element.label)
            if predicate(value) { return value }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return value
    }

    /// "Next image" tags the asset as culled; "previous image" rolls that back.
    @MainActor
    func testNextAndPreviousImage() throws {
        let app = try launchConnectedApp()

        let cullAll = app.buttons["Cull Entire Roll"]
        XCTAssertTrue(cullAll.waitForExistence(timeout: 20))
        forceTap(cullAll)

        let firstCard = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 of'")).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 60), "First card should load")

        app.swipeLeft() // next image → tags `culled`
        let secondCard = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '2 of'")).firstMatch
        XCTAssertTrue(secondCard.waitForExistence(timeout: 20), "Next image should advance")
        sleep(2)
        attachScreenshot(of: app, named: "real-second-card")

        app.swipeRight() // previous image → un-tags
        XCTAssertTrue(firstCard.waitForExistence(timeout: 20), "Previous image should step back")
        sleep(2)
        attachScreenshot(of: app, named: "real-back-to-first")
    }

    /// Reads the badge once it stops changing (two equal reads a second apart).
    @MainActor
    private func settledBadgeCount(_ element: XCUIElement, attempts: Int = 15) -> Int {
        var previous = Self.badgeCount(element.label)
        for _ in 0..<attempts {
            Thread.sleep(forTimeInterval: 1)
            let current = Self.badgeCount(element.label)
            if current == previous && current > 0 { return current }
            previous = current
        }
        return previous
    }

    /// Parses "Trash bin, 20 items" → 20; plain "Trash bin" → 0.
    private static func badgeCount(_ label: String) -> Int {
        let digits = label.split(whereSeparator: { !$0.isNumber })
        return digits.first.flatMap { Int($0) } ?? 0
    }
}
