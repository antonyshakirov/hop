import XCTest
@testable import HopCore

final class PackageReceiptsTests: XCTestCase {
    private let files = ["Applications", "Applications/Blackmagic RAW",
                         "Applications/Blackmagic RAW/Blackmagic RAW Player.app",
                         "Applications/Blackmagic RAW/Blackmagic RAW Player.app/Contents",
                         "Applications/Blackmagic RAW/Blackmagic RAW Player.app/Contents/Helpers/Tool.app",
                         "Applications/Blackmagic RAW/Blackmagic RAW Speed Test.app"]

    func testOnlyTheOutermostBundlesCount() {
        XCTAssertEqual(PackageReceipts.appBundles(in: files, prefix: "/"),
                       ["/Applications/Blackmagic RAW/Blackmagic RAW Player.app",
                        "/Applications/Blackmagic RAW/Blackmagic RAW Speed Test.app"])
    }

    func testThePrefixIsWhereThePackageWasInstalled() {
        XCTAssertEqual(PackageReceipts.appBundles(in: ["Microsoft Word.app/Contents"], prefix: "Applications"),
                       ["/Applications/Microsoft Word.app"])
    }

    func testEveryAppGoneMakesARemovedApp() {
        XCTAssertEqual(PackageReceipts.removedApps(files: files, prefix: "/", exists: { _ in false },
                                                   installedNames: [])?.count, 2)
    }

    func testOneAppStillInPlaceKeepsTheRecord() {
        XCTAssertNil(PackageReceipts.removedApps(files: files, prefix: "/",
                                                 exists: { $0.hasSuffix("Speed Test.app") }, installedNames: []))
    }

    func testAnAppMovedElsewhereIsNotRemoved() {
        XCTAssertNil(PackageReceipts.removedApps(files: files, prefix: "/", exists: { _ in false },
                                                 installedNames: ["Blackmagic RAW Player.app"]))
    }

    func testAPackageWithNoAppIsNotAnApp() {
        XCTAssertNil(PackageReceipts.removedApps(files: ["Library/Fonts/A.ttf"], prefix: "/",
                                                 exists: { _ in false }, installedNames: []))
    }

    func testApplesRecordsAreLeftAlone() {
        XCTAssertFalse(PackageReceipts.isOffered(receipt: "com.apple.pkg.Xcode"))
        XCTAssertTrue(PackageReceipts.isOffered(receipt: "com.blackmagic-design.BlackmagicRaw_resolve"))
    }
}
