import Darwin
import Foundation
import Security
import XCTest
@testable import HopHardwareKit

final class HardwareJournalTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hardware-journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testJournalPersistsAcrossReopenAndExcludesAnotherOwner() throws {
        let url = try directory()
        let journal = FileHardwareJournal(path: url.path, expectedUID: geteuid())
        let competitor = FileHardwareJournal(path: url.path, expectedUID: geteuid())
        try journal.acquire()
        XCTAssertThrowsError(try competitor.acquire())
        let record = HardwareRecovery(sleepDisabledBefore: false, fans: [0, 2])
        try journal.save(record)
        XCTAssertEqual(try journal.load(), record)
        journal.release()
        try competitor.acquire()
        XCTAssertEqual(try competitor.load(), record)
        try competitor.clear(); competitor.release()
        try journal.acquire(); XCTAssertNil(try journal.load()); journal.release()
    }

    func testSymlinksPermissionsAndMalformedRecordsAreRejected() throws {
        let url = try directory(), target = url.appendingPathComponent("target")
        try Data("untouched".utf8).write(to: target)
        let record = url.appendingPathComponent("recovery.json")
        try FileManager.default.createSymbolicLink(at: record, withDestinationURL: target)
        let journal = FileHardwareJournal(path: url.path, expectedUID: geteuid())
        try journal.acquire()
        XCTAssertThrowsError(try journal.load())
        XCTAssertEqual(try String(contentsOf: target), "untouched")
        try FileManager.default.removeItem(at: record)
        try Data("broken".utf8).write(to: record)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
        XCTAssertThrowsError(try journal.load())
        journal.release()
        let unsafe = try directory()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unsafe.path)
        XCTAssertThrowsError(try FileHardwareJournal(path: unsafe.path, expectedUID: geteuid()).acquire())
    }

    func testNativeClamshellPolicyDoesNotSleepAnOpenLidOrExternalDisplayMode() throws {
        XCTAssertTrue(try SystemHardwareBackend.closedLidRequiresSleep(lidClosed: true, causesSleep: true))
        XCTAssertFalse(try SystemHardwareBackend.closedLidRequiresSleep(lidClosed: false, causesSleep: true))
        XCTAssertFalse(try SystemHardwareBackend.closedLidRequiresSleep(lidClosed: true, causesSleep: false))
        XCTAssertFalse(try SystemHardwareBackend.closedLidRequiresSleep(lidClosed: false, causesSleep: nil))
        XCTAssertThrowsError(try SystemHardwareBackend.closedLidRequiresSleep(lidClosed: true, causesSleep: nil))
        XCTAssertThrowsError(try SystemHardwareBackend.closedLidRequiresSleep(lidClosed: nil, causesSleep: true))
    }

    func testLegacyRecoveryDecodesWithoutAppliedStageAndInvalidStagesAreRejected() throws {
        let legacy = try JSONDecoder().decode(HardwareRecovery.self,
            from: Data(#"{"sleepDisabledBefore":false,"fans":[]}"#.utf8))
        XCTAssertFalse(legacy.lidOverrideApplied); XCTAssertTrue(legacy.valid)
        let applied = HardwareRecovery(sleepDisabledBefore: false, lidOverrideApplied: true)
        XCTAssertTrue(applied.valid)
        XCTAssertEqual(try JSONDecoder().decode(HardwareRecovery.self,
            from: JSONEncoder().encode(applied)), applied)
        XCTAssertFalse(HardwareRecovery(sleepDisabledBefore: false, sleepOverrideRestored: true).valid)
        XCTAssertFalse(HardwareRecovery(lidOverrideApplied: true).valid)
        XCTAssertFalse(HardwareRecovery(sleepDisabledBefore: true, lidOverrideApplied: true).valid)
    }

    func testPowerReadbackIsExactAndMissingOrConflictingOutputIsUnknown() {
        XCTAssertEqual(SystemHardwareBackend.parseSleepDisabled(" sleep 10\n SleepDisabled 0\n"), false)
        XCTAssertEqual(SystemHardwareBackend.parseSleepDisabled("SleepDisabled 1\n"), true)
        for text in ["", "sleep 10", "SleepDisabled 10", "SleepDisabled unknown", "SleepDisabled 0\nSleepDisabled 1", "SleepDisabled 0 (1)"] {
            XCTAssertNil(SystemHardwareBackend.parseSleepDisabled(text))
        }
    }

    func testCodeRequirementRejectsUnknownIdentityAndParsesForBothAppVariants() throws {
        for app in HardwareIdentity.applications {
            for identifier in [app, app + HardwareIdentity.helperSuffix] {
                let text = try XCTUnwrap(HardwareIdentity.requirement(identifier: identifier, team: "ABCDEFGHIJ"))
                var requirement: SecRequirement?
                XCTAssertEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess)
                XCTAssertNotNil(requirement)
            }
        }
        XCTAssertNil(HardwareIdentity.requirement(identifier: "another.app", team: "ABCDEFGHIJ"))
        XCTAssertNil(HardwareIdentity.requirement(identifier: HardwareIdentity.applications[0], team: "A\" or true"))
    }
}
