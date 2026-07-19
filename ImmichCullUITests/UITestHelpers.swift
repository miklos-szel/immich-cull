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

    /// Restores the mock server's fixture so each test starts from the same
    /// content regardless of what earlier tests trashed or tagged.
    func resetMockServer(file: StaticString = #filePath, line: UInt = #line) {
        guard let url = URL(string: "http://127.0.0.1:2283/__test__/reset") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5

        let finished = DispatchSemaphore(value: 0)
        var failure: String?
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                failure = error.localizedDescription
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = "HTTP \(http.statusCode)"
            }
            finished.signal()
        }.resume()

        if finished.wait(timeout: .now() + 10) == .timedOut {
            failure = "timed out"
        }
        if let failure {
            XCTFail("Could not reset the mock server: \(failure)", file: file, line: line)
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
