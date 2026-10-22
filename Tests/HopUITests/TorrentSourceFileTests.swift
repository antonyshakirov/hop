import XCTest
@testable import Hop

final class TorrentSourceFileTests: XCTestCase {
    func testPersistedSourceMovesOnlyTheOriginalAndKeepsDownloads() throws {
        try withFiles { source, payload, data in
            let reference = TorrentSourceFile(url: source, data: data)
            let restored = try JSONDecoder().decode(TorrentSourceFile.self, from: JSONEncoder().encode(reference))
            let trash = source.deletingLastPathComponent().appendingPathComponent("discarded.torrent")
            try restored.trash { try FileManager.default.moveItem(at: $0, to: trash) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(try Data(contentsOf: trash), data)
            XCTAssertEqual(try Data(contentsOf: payload), Data("download".utf8))
        }
    }

    func testReplacedSourceIsNotDeleted() throws {
        try withFiles { source, payload, data in
            let reference = TorrentSourceFile(url: source, data: data)
            try Data("replacement".utf8).write(to: source)
            XCTAssertThrowsError(try reference.trash { _ in XCTFail("must not trash a changed source") })
            XCTAssertEqual(try Data(contentsOf: source), Data("replacement".utf8))
            XCTAssertTrue(FileManager.default.fileExists(atPath: payload.path))
        }
    }

    func testMissingSourceDoesNotBlockRemoval() throws {
        try withFiles { source, _, data in
            let reference = TorrentSourceFile(url: source, data: data)
            try FileManager.default.removeItem(at: source)
            XCTAssertNoThrow(try reference.trash { _ in XCTFail("missing source must not be trashed") })
        }
    }

    func testSymlinkCannotDeleteItsTarget() throws {
        try withFiles { source, payload, data in
            let reference = TorrentSourceFile(url: source, data: data)
            try FileManager.default.removeItem(at: source)
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: payload)
            XCTAssertThrowsError(try reference.trash { _ in XCTFail("must reject symlink") })
            XCTAssertEqual(try Data(contentsOf: payload), Data("download".utf8))
        }
    }

    func testFailedMoveLeavesSourceAndDownloadOnDisk() throws {
        try withFiles { source, payload, data in
            let reference = TorrentSourceFile(url: source, data: data)
            XCTAssertThrowsError(try reference.trash { _ in throw CocoaError(.fileWriteNoPermission) })
            XCTAssertEqual(try Data(contentsOf: source), data)
            XCTAssertTrue(FileManager.default.fileExists(atPath: payload.path))
        }
    }

    private func withFiles(_ body: (URL, URL, Data) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.torrent")
        let payload = folder.appendingPathComponent("download.bin")
        let data = Data("d4:infod4:name8:downloadee".utf8)
        try data.write(to: source)
        try Data("download".utf8).write(to: payload)
        try body(source, payload, data)
    }
}
