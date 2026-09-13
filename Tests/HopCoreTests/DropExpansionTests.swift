import XCTest
@testable import HopCore

final class DropExpansionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropExpansionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
        return url
    }

    private func names(_ urls: [URL]) -> Set<String> {
        Set(urls.map(\.lastPathComponent))
    }

    func testAFileStaysItself() throws {
        let photo = try file("photo.jpg")
        XCTAssertEqual(DropExpansion.expand([photo]), [photo])
    }

    func testAFolderGivesItsFilesAtAnyDepth() throws {
        _ = try file("shoot/a.jpg")
        _ = try file("shoot/day two/b.jpg")
        XCTAssertEqual(names(DropExpansion.expand([root.appendingPathComponent("shoot")])),
                       ["a.jpg", "b.jpg"])
    }

    func testADroppedPackageStaysOneItem() throws {
        _ = try file("Tool.app/Contents/Info.plist")
        _ = try file("Tool.app/Contents/MacOS/Tool")
        let app = root.appendingPathComponent("Tool.app")
        XCTAssertEqual(DropExpansion.expand([app]), [app])
    }

    func testAPackageInsideAFolderIsKeptWhole() throws {
        _ = try file("docs/notes.rtfd/TXT.rtf")
        _ = try file("docs/readme.md")
        XCTAssertEqual(names(DropExpansion.expand([root.appendingPathComponent("docs")])),
                       ["notes.rtfd", "readme.md"])
    }

    func testHiddenFilesAreSkipped() throws {
        _ = try file("shoot/.DS_Store")
        _ = try file("shoot/a.jpg")
        XCTAssertEqual(names(DropExpansion.expand([root.appendingPathComponent("shoot")])),
                       ["a.jpg"])
    }

    func testAFolderStopsAtTheLimit() throws {
        for index in 0..<5 { _ = try file("many/\(index).jpg") }
        XCTAssertEqual(DropExpansion.expand([root.appendingPathComponent("many")], limit: 3).count, 3)
    }

    func testTheLimitIsCountedPerFolder() throws {
        for index in 0..<3 {
            _ = try file("one/\(index).jpg")
            _ = try file("two/\(index).jpg")
        }
        let folders = [root.appendingPathComponent("one"), root.appendingPathComponent("two")]
        XCTAssertEqual(DropExpansion.expand(folders, limit: 2).count, 4)
    }

    func testAMissingPathIsDropped() {
        XCTAssertEqual(DropExpansion.expand([root.appendingPathComponent("gone.jpg")]), [])
    }

    func testAWebAddressPassesThrough() throws {
        let address = try XCTUnwrap(URL(string: "https://example.com/post"))
        XCTAssertEqual(DropExpansion.expand([address]), [address])
    }

    func testOrderFollowsTheDrop() throws {
        let first = try file("b.jpg")
        let second = try file("a.jpg")
        XCTAssertEqual(DropExpansion.expand([first, second]), [first, second])
    }
}
