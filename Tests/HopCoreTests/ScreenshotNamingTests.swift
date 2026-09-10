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

    // MARK: - Where the file goes

    /// SPEC: docs/spec.md — "Screenshot": with nothing chosen a shot lands on
    /// the desktop, the same place the system's own capture puts it.
    func testAShotGoesToTheDesktopUntilSomewhereElseIsChosen() {
        let desktop = URL(fileURLWithPath: "/Users/x/Desktop")
        let folder = ScreenshotNaming.folder(
            stored: nil, desktop: desktop, home: URL(fileURLWithPath: "/Users/x"))
        XCTAssertEqual(folder, desktop)
    }

    func testAChosenFolderWins() {
        let folder = ScreenshotNaming.folder(
            stored: "/Users/x/Shots",
            desktop: URL(fileURLWithPath: "/Users/x/Desktop"),
            home: URL(fileURLWithPath: "/Users/x"))
        XCTAssertEqual(folder.path, "/Users/x/Shots")
    }

    /// A setting cleared to an empty string is no setting at all — the default
    /// answers, rather than the shot landing at the root of the disk.
    func testAnEmptySettingIsNoSetting() {
        let desktop = URL(fileURLWithPath: "/Users/x/Desktop")
        XCTAssertEqual(
            ScreenshotNaming.folder(stored: "", desktop: desktop,
                                    home: URL(fileURLWithPath: "/Users/x")),
            desktop)
    }

    func testTheHomeFolderAnswersWhenThereIsNoDesktop() {
        let home = URL(fileURLWithPath: "/Users/x")
        XCTAssertEqual(ScreenshotNaming.folder(stored: nil, desktop: nil, home: home), home)
    }

    // MARK: - A name typed by hand

    /// SPEC: docs/spec.md — "Screenshot", the name field. A slash made the
    /// name a path into a folder that does not exist, and the save failed.
    func testASlashCannotLeadOutOfTheFolder() {
        XCTAssertEqual(ScreenshotNaming.cleaned("../../etc/shot", format: "png"), "etc-shot.png")
        XCTAssertEqual(ScreenshotNaming.cleaned("a/b:c", format: "png"), "a-b-c.png")
    }

    func testANameWithoutItsExtensionGetsOne() {
        XCTAssertEqual(ScreenshotNaming.cleaned("report", format: "jpg"), "report.jpg")
        XCTAssertEqual(ScreenshotNaming.cleaned("report.PNG", format: "png"), "report.PNG")
        XCTAssertEqual(ScreenshotNaming.cleaned("report.jpeg", format: "jpg"), "report.jpeg")
    }

    /// The format decides what is written, so a name claiming another one
    /// keeps its words and gets the true extension after them.
    func testANameClaimingAnotherFormatGetsTheRealOne() {
        XCTAssertEqual(ScreenshotNaming.cleaned("report.png", format: "jpg"), "report.png.jpg")
    }

    func testAHiddenOrEmptyNameIsNoName() {
        XCTAssertNil(ScreenshotNaming.cleaned("   ", format: "png"))
        XCTAssertNil(ScreenshotNaming.cleaned("..", format: "png"))
        XCTAssertEqual(ScreenshotNaming.cleaned(".shot", format: "png"), "shot.png")
    }
}
