import XCTest
@testable import HopCore

/// The installer finder is deliberately narrow, and these tests are what keeps it
/// that way: every widening of the net is a chance to delete something wanted.
final class InstallerFilesTests: XCTestCase {

    func testTheThreeInstallerTypesAreRecognised() {
        XCTAssertTrue(InstallerFiles.isInstaller("Hop.dmg"))
        XCTAssertTrue(InstallerFiles.isInstaller("driver.pkg"))
        XCTAssertTrue(InstallerFiles.isInstaller("suite.mpkg"))
        XCTAssertTrue(InstallerFiles.isInstaller("HOP.DMG"), "extensions are not case-sensitive")
    }

    func testEverythingElseIsLeftAlone() {
        // an iso may be a film, a zip may be a year of work
        for name in ["holiday.iso", "project.zip", "notes.txt", "Foo.app", "archive.tar.gz"] {
            XCTAssertFalse(InstallerFiles.isInstaller(name), name)
        }
    }

    func testOnlyTheFoldersADownloadLandsIn() {
        XCTAssertEqual(InstallerFiles.folders, ["Downloads", "Desktop", "Documents"])
    }

    func testNothingIsTickedByDefault() {
        XCTAssertFalse(InstallerFiles.tickedByDefault,
                       "an installer on disk is somebody's choice")
    }

    func testBiggestFirst() {
        let now = Date(timeIntervalSince1970: 0)
        let small = InstallerFiles.Found(path: "/a.dmg", bytes: 10, modified: now)
        let big = InstallerFiles.Found(path: "/b.dmg", bytes: 2_000, modified: now)
        XCTAssertEqual(InstallerFiles.sorted([small, big]).map(\.path), ["/b.dmg", "/a.dmg"])
    }
}
