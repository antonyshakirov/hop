import Foundation
import XCTest
@testable import Hop

final class UpdateBundleSwapTests: XCTestCase {
    func testAtomicExchangeAndRollbackPreserveBothCompleteBundles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-swap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appendingPathComponent("installed.app"), candidate = directory.appendingPathComponent("candidate.app")
        for (url, content) in [(old, "old"), (candidate, "new")] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url.appendingPathComponent("binary"))
        }
        var swap = UpdateBundleSwap(installed: old, candidate: candidate)
        try swap.exchange()
        XCTAssertEqual(try String(contentsOf: old.appendingPathComponent("binary")), "new")
        XCTAssertEqual(try String(contentsOf: candidate.appendingPathComponent("binary")), "old")
        try swap.rollback(); try swap.rollback()
        XCTAssertEqual(try String(contentsOf: old.appendingPathComponent("binary")), "old")
        XCTAssertEqual(try String(contentsOf: candidate.appendingPathComponent("binary")), "new")
    }

    func testMissingCandidateCannotRemoveTheInstalledBundle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-swap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let installed = directory.appendingPathComponent("installed.app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: installed.appendingPathComponent("binary"))
        var swap = UpdateBundleSwap(installed: installed, candidate: directory.appendingPathComponent("missing.app"))
        XCTAssertThrowsError(try swap.exchange())
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("binary")), "old")
        XCTAssertFalse(swap.exchanged)
    }
}
