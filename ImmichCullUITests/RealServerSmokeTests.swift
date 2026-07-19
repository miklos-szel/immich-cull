import XCTest

/// Optional smoke test against a real Immich server. Runs only when
/// REAL_SERVER_URL / REAL_SERVER_API_KEY are set in the test environment.
/// Performs a single "keep" swipe (tags one asset) — nothing is trashed.
final class RealServerSmokeTests: XCTestCase {
    @MainActor
    func testShowsRealAssetsAndKeepsOne() throws {
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
        ]
        app.launch()

        let cullAll = app.buttons["Cull Entire Roll"]
        XCTAssertTrue(cullAll.waitForExistence(timeout: 15), "Should land on Home when preconfigured")
        attachScreenshot(of: app, named: "real-home")
        forceTap(cullAll)

        let progress = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 of'")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 30), "First card should load from the real server")
        sleep(4) // Give the video/image time to render for the screenshot.
        attachScreenshot(of: app, named: "real-first-card")

        app.swipeLeft() // keep: tags the asset as culled, nothing destructive
        let progress2 = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '2 of'")).firstMatch
        XCTAssertTrue(progress2.waitForExistence(timeout: 10), "Keep swipe should advance to the next card")
        sleep(2)
        attachScreenshot(of: app, named: "real-second-card")
    }
}
