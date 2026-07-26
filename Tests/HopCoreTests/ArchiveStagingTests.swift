import XCTest
@testable import HopCore

final class ArchiveStagingTests: XCTestCase {
    private enum TestError: Error { case failed }

    func testManagedNamesRequireExactUUIDShape() {
        let session = UUID()
        let operation = UUID()

        XCTAssertTrue(
            ArchiveStaging.isManagedDirectoryName(
                ArchiveStaging.directoryName(
                    sessionID: session,
                    operationID: operation)))
        XCTAssertTrue(
            ArchiveStaging.isManagedDirectoryName(
                ".hop-unpack-\(operation.uuidString)"))
        XCTAssertFalse(
            ArchiveStaging.isManagedDirectoryName(".hop-unpack-notes"))
        XCTAssertFalse(
            ArchiveStaging.isManagedDirectoryName(
                ".hop-unpack-\(session.uuidString)--not-a-uuid"))
    }

    func testCleanupRemovesOldDirectoriesAndPreservesCurrentSession() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let current = UUID()
        let old = UUID()
        let legacy = root.appendingPathComponent(".hop-unpack-\(UUID().uuidString)")
        let oldSession = root.appendingPathComponent(
            ArchiveStaging.directoryName(sessionID: old, operationID: UUID()))
        let currentSession = root.appendingPathComponent(
            ArchiveStaging.directoryName(sessionID: current, operationID: UUID()))
        for url in [legacy, oldSession, currentSession] {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: false)
        }

        try ArchiveStaging.removeOrphans(
            in: root,
            preserving: current)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldSession.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentSession.path))
    }

    func testCleanupIgnoresSimilarNamesFilesAndSymlinks() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let similar = root.appendingPathComponent(".hop-unpack-notes")
        let managedFile = root.appendingPathComponent(".hop-unpack-\(UUID().uuidString)")
        let target = root.appendingPathComponent("real-folder")
        let managedLink = root.appendingPathComponent(".hop-unpack-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: similar,
            withIntermediateDirectories: false)
        XCTAssertTrue(FileManager.default.createFile(
            atPath: managedFile.path,
            contents: Data("keep".utf8)))
        try FileManager.default.createDirectory(
            at: target,
            withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: managedLink,
            withDestinationURL: target)

        try ArchiveStaging.removeOrphans(
            in: root,
            preserving: UUID())

        XCTAssertTrue(FileManager.default.fileExists(atPath: similar.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedFile.path))
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(
            atPath: managedLink.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testOperationRemovesItsDirectoryAfterSuccess() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var staging: URL?

        let value: String = try ArchiveStaging.withDirectory(
            in: root,
            sessionID: UUID()
        ) { directory in
            staging = directory
            return "done"
        }

        XCTAssertEqual(value, "done")
        XCTAssertNotNil(staging)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging!.path))
    }

    func testOperationRemovesItsDirectoryAfterError() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var staging: URL?

        XCTAssertThrowsError(
            try ArchiveStaging.withDirectory(
                in: root,
                sessionID: UUID()
            ) { directory in
                staging = directory
                throw TestError.failed
            } as Void
        )

        XCTAssertNotNil(staging)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging!.path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hop-staging-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false)
        return url
    }
}
