import XCTest

/// The capture-time rule `PhotoLibraryService` uses before deleting a local
/// photo. A false match deletes the wrong photo, so the rule is tight.
final class PhotoMatchingTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    func testSameInstantMatches() {
        XCTAssertTrue(PhotoLibraryService.datesMatch(base, base.addingTimeInterval(30)))
    }

    /// Immich can be off by a whole timezone offset when EXIF had no zone.
    func testWholeTimezoneOffsetsMatch() {
        XCTAssertTrue(PhotoLibraryService.datesMatch(base, base.addingTimeInterval(2 * 3600)))
        XCTAssertTrue(PhotoLibraryService.datesMatch(base, base.addingTimeInterval(-(5 * 3600 + 30 * 60))))
        XCTAssertTrue(PhotoLibraryService.datesMatch(base, base.addingTimeInterval(9 * 3600 + 45 * 60 + 60)))
    }

    func testOffsetsThatAreNoTimezoneDoNotMatch() {
        XCTAssertFalse(PhotoLibraryService.datesMatch(base, base.addingTimeInterval(10 * 60)))
        XCTAssertFalse(PhotoLibraryService.datesMatch(base, base.addingTimeInterval(3600 + 7 * 60)))
    }

    func testBeyondAnyTimezoneDoesNotMatch() {
        XCTAssertFalse(PhotoLibraryService.datesMatch(base, base.addingTimeInterval(15 * 3600)))
    }

    /// Missing a date used to mean "match on filename alone".
    func testMissingDateNeverMatches() {
        XCTAssertFalse(PhotoLibraryService.datesMatch(nil, base))
        XCTAssertFalse(PhotoLibraryService.datesMatch(base, nil))
    }
}
