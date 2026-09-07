import XCTest
@testable import HopCore

final class ScreenshotNamingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testTheNameCarriesTheDateAndTheFormat() {
        let date = Date(timeIntervalSince1970: 1_788_000_000)
        let name = ScreenshotNaming.fileName(at: date, calendar: calendar, format: "png")
        XCTAssertTrue(name.hasSuffix(".png"), name)
        XCTAssertTrue(name.contains("2026-"), name)
    }

    func testTheFormatIsTheOneAskedFor() {
        let date = Date(timeIntervalSince1970: 1_788_000_000)
        XCTAssertTrue(ScreenshotNaming.fileName(at: date, calendar: calendar, format: "jpg").hasSuffix(".jpg"))
    }

    /// Two shots inside one minute must not overwrite each other.
    func testASecondShotInTheSameMinuteGetsASuffix() {
        let taken: Set<String> = ["shot 2026-09-07 at 18.41.png"]
        let unique = ScreenshotNaming.unique("shot 2026-09-07 at 18.41.png", taken: taken)
        XCTAssertNotEqual(unique, "shot 2026-09-07 at 18.41.png")
        XCTAssertTrue(unique.hasSuffix(".png"), unique)
        XCTAssertTrue(unique.contains("2026-09-07"), unique)
    }

    func testTheSuffixCountsPastEveryNameAlreadyTaken() {
        let taken: Set<String> = [
            "shot.png", "shot 2.png", "shot 3.png",
        ]
        XCTAssertEqual(ScreenshotNaming.unique("shot.png", taken: taken), "shot 4.png")
    }

    func testAFreeNameIsLeftAlone() {
        XCTAssertEqual(ScreenshotNaming.unique("shot.png", taken: []), "shot.png")
    }
}
