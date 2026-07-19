import XCTest

extension XCTestCase {
    /// iOS 26 elements often report a bogus hit point; fall back to a frame-center coordinate tap.
    @MainActor
    func forceTap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// Scrolls a list until the element's frame is fully inside the visible
    /// area. isHittable can falsely report true on iOS 26, so trust geometry.
    @MainActor
    func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 5) {
        let visible = app.windows.firstMatch.frame.insetBy(dx: 0, dy: 150)
        var tries = 0
        while !visible.contains(element.frame) && tries < maxSwipes {
            app.swipeUp()
            tries += 1
        }
    }

    /// Waits for an element's label to satisfy a predicate. Needed wherever a
    /// label is driven by an async server round-trip (e.g. the trash badge).
    @MainActor
    func waitForLabel(_ element: XCUIElement, matching predicateFormat: String, timeout: TimeInterval = 20) {
        expectation(for: NSPredicate(format: predicateFormat), evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    @MainActor
    func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
