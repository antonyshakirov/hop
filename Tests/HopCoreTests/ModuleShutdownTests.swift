import XCTest
@testable import HopCore

/// SPEC: docs/spec.md — "Switching a module off".
final class ModuleShutdownTests: XCTestCase {

    func testAnIdleModuleIsSwitchedOffWithoutAQuestion() {
        let quiet = ModuleShutdown.Activity()
        for module in ModuleCatalog.allIDs {
            XCTAssertNil(ModuleShutdown.consequence(module: module, activity: quiet), module)
            XCTAssertFalse(ModuleShutdown.needsConfirmation(module: module, activity: quiet), module)
        }
    }

    func testEachBusyModuleNamesWhatItWillStop() {
        XCTAssertEqual(
            ModuleShutdown.consequence(module: "timer",
                                       activity: .init(timerRunning: true)),
            .countdownStops)
        XCTAssertEqual(
            ModuleShutdown.consequence(module: "awake",
                                       activity: .init(keepAwakeActive: true)),
            .sleepAllowedAgain)
        XCTAssertEqual(
            ModuleShutdown.consequence(module: "tracker",
                                       activity: .init(trackerRunning: true)),
            .openStretchFiled)
        XCTAssertEqual(
            ModuleShutdown.consequence(module: "torrent",
                                       activity: .init(activeDownloads: 2)),
            .downloadsPause)
        XCTAssertEqual(
            ModuleShutdown.consequence(module: "todos",
                                       activity: .init(armedReminders: 1)),
            .remindersGoQuiet)
    }

    func testTheTwoJobModulesShareTheirSentence() {
        XCTAssertEqual(
            ModuleShutdown.consequence(module: "convert",
                                       activity: .init(converterBusy: true)),
            .jobFinishesInItsWindow)
        XCTAssertEqual(
            ModuleShutdown.consequence(module: "archive",
                                       activity: .init(archiveRunning: true)),
            .jobFinishesInItsWindow)
    }

    func testAModuleAnswersOnlyForItself() {
        let busy = ModuleShutdown.Activity(timerRunning: true, keepAwakeActive: true,
                                           trackerRunning: true, activeDownloads: 3,
                                           converterBusy: true, archiveRunning: true,
                                           armedReminders: 5)
        XCTAssertNil(ModuleShutdown.consequence(module: "clipboard", activity: busy))
        XCTAssertNil(ModuleShutdown.consequence(module: "system", activity: busy))
        XCTAssertNil(ModuleShutdown.consequence(module: "vpn", activity: busy))
        XCTAssertNil(ModuleShutdown.consequence(module: "nothing-of-the-sort", activity: busy))
        XCTAssertEqual(ModuleShutdown.consequence(module: "timer", activity: busy), .countdownStops)
    }

    func testPausedDownloadsAreNotBusy() {
        XCTAssertNil(ModuleShutdown.consequence(module: "torrent",
                                                activity: .init(activeDownloads: 0)))
    }
}
