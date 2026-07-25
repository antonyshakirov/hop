import XCTest
@testable import HopCore

final class ArchiveRulesTests: XCTestCase {
    // MARK: - format recognition

    func testPlainFormats() {
        XCTAssertEqual(ArchiveRules.format(ofFileNamed: "photos.zip"), .zip)
        XCTAssertEqual(ArchiveRules.format(ofFileNamed: "backup.tar"), .tar)
        XCTAssertEqual(ArchiveRules.format(ofFileNamed: "notes.7z"), .sevenZip)
        XCTAssertEqual(ArchiveRules.format(ofFileNamed: "movie.rar"), .rar)
        XCTAssertEqual(ArchiveRules.format(ofFileNamed: "dump.gz"), .gzip)
    }

    func testCompoundExtensionsWinOverTheirTail() {
        // ".tar.gz" must not be read as a bare ".gz"
        XCTAssertEqual(ArchiveRules.format(ofFileNamed: "photos.tar.gz"), .tarGz)
        XCTAssertEqual(ArchiveRules.format(ofFileNamed: "photos.tgz"), .tarGz)
        XCTAssertEqual(ArchiveRules.format(ofFileNamed: "src.tar.bz2"), .tarBz2)
        XCTAssertEqual(ArchiveRules.format(ofFileNamed: "src.tbz2"), .tarBz2)
        XCTAssertEqual(ArchiveRules.format(ofFileNamed: "src.tar.xz"), .tarXz)
        XCTAssertEqual(ArchiveRules.format(ofFileNamed: "src.txz"), .tarXz)
    }

    func testRecognitionIsCaseInsensitive() {
        XCTAssertEqual(ArchiveRules.format(ofFileNamed: "PHOTOS.ZIP"), .zip)
        XCTAssertEqual(ArchiveRules.format(ofFileNamed: "Photos.Tar.Gz"), .tarGz)
    }

    func testNonArchivesAndDotfiles() {
        XCTAssertNil(ArchiveRules.format(ofFileNamed: "report.pages"))
        XCTAssertNil(ArchiveRules.format(ofFileNamed: "photo.png"))
        XCTAssertNil(ArchiveRules.format(ofFileNamed: ""))
        XCTAssertNil(ArchiveRules.format(ofFileNamed: ".zip"))   // no stem — a dotfile
        XCTAssertNil(ArchiveRules.format(ofFileNamed: ".tar.gz"))
    }

    func testNativeFormatsNeedNoHelper() {
        for format in ArchiveFormat.allCases {
            let needsHelper = format == .sevenZip || format == .rar
            XCTAssertEqual(format.isNative, !needsHelper, "\(format)")
        }
    }

    func testRarIsNotAPackFormat() {
        // creating .rar is legally impossible for us — the list must never offer it
        XCTAssertFalse(PackFormat.allCases.map(\.fileExtension).contains("rar"))
        XCTAssertEqual(PackFormat.allCases.map(\.fileExtension), ["zip", "tar.gz", "7z"])
    }

    // MARK: - base names

    func testBaseNameStripsTheWholeExtension() {
        XCTAssertEqual(ArchiveRules.baseName(ofArchive: "photos.tar.gz"), "photos")
        XCTAssertEqual(ArchiveRules.baseName(ofArchive: "photos.zip"), "photos")
        XCTAssertEqual(ArchiveRules.baseName(ofArchive: "my.notes.7z"), "my.notes")
    }

    func testBaseNameFallsBackToTheWholeName() {
        XCTAssertEqual(ArchiveRules.baseName(ofArchive: "README"), "README")
    }

    // MARK: - unique names

    func testUniqueNameIsUntouchedWhenFree() {
        XCTAssertEqual(
            ArchiveRules.uniqueName(base: "photos", extension: "zip", taken: []),
            "photos.zip")
    }

    func testUniqueNameCountsUpBeforeTheExtension() {
        let taken: Set<String> = ["photos.zip", "photos 2.zip"]
        XCTAssertEqual(
            ArchiveRules.uniqueName(base: "photos", extension: "zip", taken: taken),
            "photos 3.zip")
    }

    func testUniqueNameHandlesExtensionlessFolders() {
        let taken: Set<String> = ["photos"]
        XCTAssertEqual(
            ArchiveRules.uniqueName(base: "photos", extension: "", taken: taken),
            "photos 2")
    }

    func testUniqueNameComparesCaseInsensitively() {
        // the default macOS volume is case-insensitive: "Photos.zip" IS taken
        let taken: Set<String> = ["Photos.zip"]
        XCTAssertEqual(
            ArchiveRules.uniqueName(base: "photos", extension: "zip", taken: taken),
            "photos 2.zip")
    }

    // MARK: - pack naming

    func testSingleFilePacksUnderItsOwnStem() {
        XCTAssertEqual(
            ArchiveRules.packBaseName(for: ["/Users/a/Desktop/report.pages"],
                                      commonParent: "/Users/a/Desktop"),
            "report")
    }

    func testSingleFolderPacksUnderItsName() {
        XCTAssertEqual(
            ArchiveRules.packBaseName(for: ["/Users/a/Desktop/shoot"],
                                      commonParent: "/Users/a/Desktop"),
            "shoot")
    }

    func testSeveralItemsPackUnderTheirFolderName() {
        XCTAssertEqual(
            ArchiveRules.packBaseName(for: ["/Users/a/shoot/one.raw", "/Users/a/shoot/two.raw"],
                                      commonParent: "/Users/a/shoot"),
            "shoot")
    }

    func testMixedDropFallsBackToArchive() {
        XCTAssertEqual(
            ArchiveRules.packBaseName(for: ["/Users/a/one.raw", "/Users/b/two.raw"],
                                      commonParent: nil),
            "archive")
        XCTAssertEqual(ArchiveRules.packBaseName(for: [], commonParent: nil), "archive")
    }

    // MARK: - common parent

    func testCommonParentOfOneFolder() {
        XCTAssertEqual(
            ArchiveRules.commonParent(of: ["/Users/a/shoot/one", "/Users/a/shoot/two"]),
            "/Users/a/shoot")
    }

    func testCommonParentOfScatteredItemsIsNil() {
        XCTAssertNil(ArchiveRules.commonParent(of: ["/Users/a/one", "/Users/b/two"]))
    }

    // MARK: - entry safety (zip slip)

    func testSafeEntryPaths() {
        XCTAssertTrue(ArchiveRules.isSafeEntryPath("photos/one.jpg"))
        XCTAssertTrue(ArchiveRules.isSafeEntryPath("one.jpg"))
        XCTAssertTrue(ArchiveRules.isSafeEntryPath("a/b/c/deep.txt"))
        // a name that merely CONTAINS dots is fine
        XCTAssertTrue(ArchiveRules.isSafeEntryPath("photos/..hidden.jpg"))
    }

    func testEscapingEntryPathsAreRejected() {
        XCTAssertFalse(ArchiveRules.isSafeEntryPath("/etc/passwd"))
        XCTAssertFalse(ArchiveRules.isSafeEntryPath("~/.ssh/id_rsa"))
        XCTAssertFalse(ArchiveRules.isSafeEntryPath("../outside.txt"))
        XCTAssertFalse(ArchiveRules.isSafeEntryPath("photos/../../outside.txt"))
    }
}
