import XCTest
@testable import HopHardwareKit

final class HardwareCoordinatorTests: XCTestCase {
    private final class Journal: HardwareJournal {
        final class Storage { var record: HardwareRecovery?; var owner: UUID? }
        let storage: Storage
        let id = UUID()
        init(storage: Storage = Storage()) { self.storage = storage }
        var record: HardwareRecovery? { get { storage.record } set { storage.record = newValue } }
        var locked: Bool { storage.owner == id }
        var rejectLock = false
        var rejectSave = false
        var rejectAfterSaves: Int?
        var saveCount = 0
        var events: [String] = []
        func acquire() throws {
            if rejectLock || (storage.owner != nil && storage.owner != id) { throw HardwareReason.busy }
            storage.owner = id
        }
        func load() throws -> HardwareRecovery? { record }
        func save(_ record: HardwareRecovery) throws {
            saveCount += 1
            if rejectSave || (rejectAfterSaves.map { saveCount > $0 } ?? false) { throw HardwareReason.commandFailed }
            self.record = record; events.append("saved")
        }
        func clear() throws { record = nil; events.append("cleared") }
        func release() { if locked { storage.owner = nil } }
    }

    private final class Backend: HardwareBackend {
        let journal: Journal
        var idleReady = false
        func idleLidReleaseReady() -> Bool { idleReady }
        var sleep = false
        var reading = HardwareObservation(fans: [.init(id: 0, rpm: 1200, minimum: 1000,
            maximum: 6000, manual: false)], temperature: 70, supportsControl: true,
            lidClosed: false, onBattery: false, batteryPercent: 70)
        var targets: [Int: Double] = [:]
        var writes = 0
        var sleepRequests = 0
        var requestedBeforeRestoration = false
        var rejectFanWrite = false
        var rejectFanRestore = false
        var rejectEnable = false
        var rejectSleepRequest = false
        var events: [String] = []
        var rejectSleepRead = false
        var rejectRestore = false
        var wroteWithoutJournal = false
        init(_ journal: Journal) { self.journal = journal }
        func observe() -> HardwareObservation { reading }
        func sleepDisabled() throws -> Bool {
            if rejectSleepRead { throw HardwareReason.commandFailed }
            return sleep
        }
        func setSleepDisabled(_ value: Bool) throws {
            if value && rejectEnable { throw HardwareReason.commandFailed }
            if !value && rejectRestore { throw HardwareReason.commandFailed }
            writes += 1; wroteWithoutJournal = wroteWithoutJournal || journal.record == nil
            sleep = value; events.append(value ? "disable-sleep" : "restore-sleep")
        }
        func restoreClosedLidBehavior() throws {
            events.append("lid-behavior")
            if rejectSleepRequest { throw HardwareReason.restoreFailed }
            if reading.lidClosed == true {
                requestedBeforeRestoration = sleep || !targets.isEmpty
                sleepRequests += 1
            }
        }
        func setFans(_ values: [Int: Double]) throws {
            writes += 1; wroteWithoutJournal = wroteWithoutJournal || journal.record == nil
            targets = values; events.append("fan-targets")
            if rejectFanWrite { throw HardwareReason.commandFailed }
        }
        func restoreFans(_ indices: [Int]) throws {
            if rejectFanRestore { throw HardwareReason.commandFailed }
            if rejectRestore { throw HardwareReason.commandFailed }
            writes += 1; wroteWithoutJournal = wroteWithoutJournal || journal.record == nil
            for index in indices { targets[index] = nil }; events.append("restore-fans")
        }
    }

    func testIdleReleaseRestoresOnlyLidWithoutDemandSleepOrRearming() {
        for manual in [false, true] {
            let journal = Journal(), owner = UUID()
            let actual = Backend(journal)
            actual.reading.lidClosed = true
            var time: Double = 10
            let coordinator = HardwareCoordinator(backend: actual, journal: journal, now: { time })
            _ = coordinator.handle(.init(.configure, configuration: .init(lid: true,
                fan: .init(mode: manual ? .maximum : .automatic), duration: 5)), owner: owner)
            actual.idleReady = true
            coordinator.tick()
            let result = coordinator.handle(.init(.status), owner: owner)
            XCTAssertFalse(result.lid); XCTAssertFalse(actual.sleep)
            XCTAssertEqual(result.active, manual)
            XCTAssertEqual(actual.sleepRequests, 0)
            XCTAssertEqual(actual.targets.isEmpty, !manual)
            time = 16
            coordinator.tick()
            XCTAssertFalse(actual.sleep)
            XCTAssertEqual(coordinator.handle(.init(.status), owner: owner).active, manual)
        }
    }

    func testFailedIdleMarkerNeverAllowsRestoreWritesOnRetry() {
        let journal = Journal(), owner = UUID()
        let backend = Backend(journal)
        backend.reading.lidClosed = true
        let coordinator = HardwareCoordinator(backend: backend, journal: journal, now: { 10 })
        _ = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner)
        let writes = backend.writes
        backend.idleReady = true; journal.rejectSave = true
        coordinator.tick(); coordinator.tick(); coordinator.shutdown()
        XCTAssertTrue(backend.sleep)
        XCTAssertEqual(backend.writes, writes)
        XCTAssertEqual(backend.sleepRequests, 0)
        XCTAssertEqual(journal.record?.idleLidRelease, false)
        journal.rejectSave = false
        coordinator.tick()
        XCTAssertFalse(backend.sleep)
        XCTAssertEqual(backend.sleepRequests, 0)
        XCTAssertNil(journal.record)
    }

    func testIdleReleaseFailureAndRestartNeverDemandSleep() {
        let journal = Journal(), owner = UUID()
        let backend = Backend(journal)
        backend.reading.lidClosed = true
        let coordinator = HardwareCoordinator(backend: backend, journal: journal, now: { 10 })
        _ = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner)
        backend.idleReady = true; backend.rejectRestore = true
        coordinator.tick()
        XCTAssertEqual(journal.record?.idleLidRelease, true)
        XCTAssertEqual(backend.sleepRequests, 0)
        journal.release(); backend.rejectRestore = false
        let restarted = HardwareCoordinator(backend: backend, journal: journal, now: { 10 })
        restarted.recoverAtLaunch()
        XCTAssertFalse(backend.sleep); XCTAssertEqual(backend.sleepRequests, 0)
        XCTAssertNil(journal.record)
    }

    func testIdleEligibilityDoesNotStopOpenLidAndUnknownEligibilityKeepsLease() {
        let journal = Journal()
        let actual = Backend(journal), owner = UUID()
        let coordinator = HardwareCoordinator(backend: actual, journal: journal, now: { 10 })
        _ = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner)
        actual.idleReady = true
        coordinator.tick(); XCTAssertTrue(actual.sleep)
        actual.idleReady = false; actual.reading.lidClosed = true
        coordinator.tick(); XCTAssertTrue(actual.sleep)
    }

    func testJournalPrecedesBothOverridesAndStopRestoresOnlyTheLease() {
        let journal = Journal(), owner = UUID()
        let backend = Backend(journal)
        let coordinator = HardwareCoordinator(backend: backend, journal: journal, now: { 10 })
        let status = coordinator.handle(.init(.configure, configuration: .init(lid: true,
            fan: .init(mode: .maximum))), owner: owner)
        XCTAssertTrue(status.active); XCTAssertTrue(status.lid)
        XCTAssertTrue(backend.sleep); XCTAssertEqual(backend.targets, [0: 6000])
        XCTAssertFalse(backend.wroteWithoutJournal)
        XCTAssertNotNil(journal.record)
        XCTAssertFalse(coordinator.handle(.init(.stop), owner: owner).active)
        XCTAssertFalse(backend.sleep); XCTAssertTrue(backend.targets.isEmpty)
        XCTAssertNil(journal.record); XCTAssertFalse(journal.locked)
    }

    func testExpiredAwakeRequestsSleepWithAlreadyClosedLidAfterRestoringFans() {
        var time: Double = 1
        let journal = Journal(), owner = UUID(), backend = Backend(journal)
        let coordinator = HardwareCoordinator(backend: backend, journal: journal, now: { time })
        _ = coordinator.handle(.init(.configure, configuration: .init(lid: true, fan: .init(mode: .maximum),
            duration: 15)), owner: owner)
        backend.reading.lidClosed = true
        time = 16; coordinator.tick()
        XCTAssertEqual(backend.sleepRequests, 1)
        XCTAssertFalse(backend.requestedBeforeRestoration)
        XCTAssertFalse(backend.sleep)
        XCTAssertEqual(coordinator.handle(.init(.status), owner: owner).reason, .expired)
        XCTAssertNil(journal.record)
    }

    func testAllClosedLidExitPathsRequestSleep() {
        for exit in 0..<6 {
            var time: Double = 1
            let journal = Journal(), backend = Backend(journal), owner = UUID()
            let coordinator = HardwareCoordinator(backend: backend, journal: journal, now: { time })
            _ = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner)
            backend.reading.lidClosed = true
            switch exit {
            case 0: _ = coordinator.handle(.init(.stop), owner: owner)
            case 1: coordinator.disconnect(owner: owner)
            case 2: time = 91; coordinator.tick()
            case 3:
                backend.reading.onBattery = true; backend.reading.batteryPercent = 10; coordinator.tick()
            case 4: backend.reading.thermalSeverity = 2; coordinator.tick()
            default: backend.reading.onBattery = nil; coordinator.tick()
            }
            XCTAssertEqual(backend.sleepRequests, 1, "exit \(exit)")
            XCTAssertFalse(backend.sleep)
        }
    }

    func testOpenLidAndFanOnlyStopDoNotRequestSleep() {
        for lid in [true, false] {
            let journal = Journal(), backend = Backend(journal), owner = UUID()
            let coordinator = HardwareCoordinator(backend: backend, journal: journal)
            _ = coordinator.handle(.init(.configure, configuration: .init(lid: lid,
                fan: .init(mode: .maximum))), owner: owner)
            backend.reading.lidClosed = !lid
            _ = coordinator.handle(.init(.stop), owner: owner)
            XCTAssertEqual(backend.sleepRequests, 0)
            XCTAssertFalse(backend.sleep)
        }
    }

    func testFailedEnableAndUnappliedRecoveryIntentDoNotRequestSleep() {
        for restart in [false, true] {
            let journal = Journal(), backend = Backend(journal)
            backend.reading.lidClosed = true
            let coordinator = HardwareCoordinator(backend: backend, journal: journal)
            if restart {
                journal.record = HardwareRecovery(sleepDisabledBefore: false)
                coordinator.recoverAtLaunch()
            } else {
                backend.rejectEnable = true
                _ = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: UUID())
            }
            XCTAssertEqual(backend.sleepRequests, 0)
            XCTAssertNil(journal.record)
        }
    }

    func testAppliedButUnmarkedOverrideIsDurableBeforeResetAndRetry() {
        let journal = Journal(), backend = Backend(journal)
        journal.record = HardwareRecovery(sleepDisabledBefore: false)
        backend.sleep = true; backend.reading.lidClosed = true; backend.rejectRestore = true
        let coordinator = HardwareCoordinator(backend: backend, journal: journal)
        coordinator.recoverAtLaunch()
        XCTAssertEqual(journal.record?.lidOverrideApplied, true)
        XCTAssertTrue(backend.sleep); XCTAssertEqual(backend.sleepRequests, 0)
        backend.rejectRestore = false; coordinator.tick()
        XCTAssertFalse(backend.sleep); XCTAssertEqual(backend.sleepRequests, 1)
        XCTAssertNil(journal.record)
    }

    func testFailedFanRestorationStillRemovesSleepOverrideAndRetainsPendingRequest() {
        let journal = Journal(), backend = Backend(journal), owner = UUID()
        let coordinator = HardwareCoordinator(backend: backend, journal: journal)
        _ = coordinator.handle(.init(.configure, configuration: .init(lid: true,
            fan: .init(mode: .maximum))), owner: owner)
        backend.reading.lidClosed = true; backend.rejectFanWrite = false
        // SPEC: simulate a fan-only restore failure without blocking the sleep flag reset.
        backend.rejectFanRestore = true
        let failed = coordinator.handle(.init(.stop), owner: owner)
        XCTAssertTrue(failed.restorationPending); XCTAssertFalse(backend.sleep)
        XCTAssertEqual(backend.sleepRequests, 0)
        XCTAssertEqual(journal.record?.lidOverrideApplied, true)
        backend.rejectFanRestore = false; coordinator.tick()
        XCTAssertEqual(backend.sleepRequests, 1); XCTAssertNil(journal.record)
    }

    func testFailedSleepRequestSurvivesResetAndHelperRestart() {
        let journal = Journal(), backend = Backend(journal), owner = UUID()
        let coordinator = HardwareCoordinator(backend: backend, journal: journal)
        _ = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner)
        backend.reading.lidClosed = true; backend.rejectSleepRequest = true
        let failed = coordinator.handle(.init(.stop), owner: owner)
        XCTAssertTrue(failed.restorationPending); XCTAssertFalse(backend.sleep)
        XCTAssertEqual(journal.record?.lidOverrideApplied, true)
        XCTAssertEqual(journal.record?.sleepOverrideRestored, true)
        backend.rejectSleepRequest = false
        let restarted = HardwareCoordinator(backend: backend, journal: journal)
        restarted.recoverAtLaunch()
        XCTAssertEqual(backend.sleepRequests, 1); XCTAssertNil(journal.record)
        XCTAssertFalse(restarted.handle(.init(.status), owner: owner).restorationPending)
    }

    func testSleepRequestRetryPreservesAForeignOverrideAppliedAfterOurReset() {
        let journal = Journal(), backend = Backend(journal), owner = UUID()
        let coordinator = HardwareCoordinator(backend: backend, journal: journal)
        _ = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner)
        backend.reading.lidClosed = true; backend.rejectSleepRequest = true
        _ = coordinator.handle(.init(.stop), owner: owner)
        XCTAssertFalse(backend.sleep)
        backend.sleep = true; backend.rejectSleepRequest = false
        let writes = backend.writes
        coordinator.tick()
        XCTAssertTrue(backend.sleep)
        XCTAssertEqual(backend.writes, writes); XCTAssertEqual(backend.sleepRequests, 0)
        XCTAssertTrue(coordinator.handle(.init(.status), owner: owner).restorationPending)
        backend.sleep = false; coordinator.tick()
        XCTAssertEqual(backend.sleepRequests, 1); XCTAssertNil(journal.record)
    }

    func testFailedAppliedJournalWriteDoesNotPreventBestEffortSleepRestoration() {
        let journal = Journal(), backend = Backend(journal), owner = UUID()
        journal.rejectAfterSaves = 1; backend.reading.lidClosed = true
        let coordinator = HardwareCoordinator(backend: backend, journal: journal)
        let failed = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner)
        XCTAssertFalse(failed.active); XCTAssertTrue(failed.restorationPending)
        XCTAssertFalse(backend.sleep)
        XCTAssertNotNil(journal.record); XCTAssertEqual(backend.sleepRequests, 1)
        journal.rejectAfterSaves = nil; coordinator.tick()
        XCTAssertFalse(backend.sleep); XCTAssertNil(journal.record)
    }

    func testDisablingLidDuringCoolingFinishesFanTransitionBeforeSleepRequest() {
        let journal = Journal(), backend = Backend(journal), owner = UUID()
        let coordinator = HardwareCoordinator(backend: backend, journal: journal)
        _ = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner)
        backend.reading.lidClosed = true; backend.events = []
        _ = coordinator.handle(.init(.configure, configuration: .init(fan: .init(mode: .maximum))), owner: owner)
        XCTAssertEqual(backend.events, ["fan-targets", "restore-sleep", "lid-behavior"])
        XCTAssertEqual(backend.sleepRequests, 1)
        XCTAssertNil(journal.record?.sleepDisabledBefore)
        XCTAssertEqual(journal.record?.lidOverrideApplied, false)
        XCTAssertEqual(backend.targets, [0: 6000])
    }

    func testRecoveryCannotQueueSleepAndAcknowledgeANewActiveSessionInOneRequest() {
        let journal = Journal(), backend = Backend(journal), owner = UUID()
        let coordinator = HardwareCoordinator(backend: backend, journal: journal)
        _ = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner)
        backend.reading.lidClosed = true; backend.rejectSleepRequest = true
        XCTAssertTrue(coordinator.handle(.init(.stop), owner: owner).restorationPending)
        backend.rejectSleepRequest = false
        let attempted = coordinator.handle(.init(.configure, configuration: .init(lid: true, duration: 7200)), owner: owner)
        XCTAssertFalse(attempted.active)
        XCTAssertEqual(attempted.reason, .busy)
        XCTAssertEqual(backend.sleepRequests, 1)
        XCTAssertFalse(backend.sleep)
        backend.reading.lidClosed = false
        XCTAssertTrue(coordinator.handle(.init(.configure, configuration: .init(lid: true, duration: 7200)), owner: owner).active)
        _ = coordinator.handle(.init(.stop), owner: owner)
    }

    func testFailedJournalPreventsEveryHardwareWrite() {
        let journal = Journal(); journal.rejectSave = true
        let backend = Backend(journal)
        let coordinator = HardwareCoordinator(backend: backend, journal: journal, now: { 1 })
        XCTAssertFalse(coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: UUID()).active)
        XCTAssertEqual(backend.writes, 0); XCTAssertFalse(backend.sleep)
    }

    func testWatchdogDeadlineUsesUptimeAndRenewDoesNotExtendSession() {
        var time: Double = 1
        let journal = Journal(), owner = UUID()
        let actual = Backend(journal)
        let coordinator = HardwareCoordinator(backend: actual, journal: journal, now: { time })
        XCTAssertTrue(coordinator.handle(.init(.configure, configuration: .init(lid: true, duration: 100)), owner: owner).active)
        time = 89; XCTAssertTrue(coordinator.handle(.init(.renew), owner: owner).active)
        time = 102; coordinator.tick()
        XCTAssertFalse(actual.sleep)
        XCTAssertEqual(coordinator.handle(.init(.status), owner: owner).reason, .expired)

    }

    func testNinetySecondsWithoutHeartbeatRestoresAndDoesNotRearm() {
        var time: Double = 1
        let journal = Journal(), owner = UUID()
        let backend = Backend(journal)
        let coordinator = HardwareCoordinator(backend: backend, journal: journal, now: { time })
        _ = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner)
        time = 91; coordinator.tick()
        XCTAssertFalse(backend.sleep)
        XCTAssertEqual(coordinator.handle(.init(.renew), owner: owner).reason, .heartbeat)
        XCTAssertFalse(coordinator.handle(.init(.status), owner: owner).active)
    }

    func testBatteryCutoffIsBatteryPowerOnlyAndRequiresLidMode() {
        let journal = Journal(), owner = UUID()
        let backend = Backend(journal)
        let coordinator = HardwareCoordinator(backend: backend, journal: journal, now: { 1 })
        backend.reading.batteryPercent = 5
        XCTAssertTrue(coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner).active)
        coordinator.tick(); XCTAssertTrue(backend.sleep)
        backend.reading.onBattery = true
        coordinator.tick(); XCTAssertFalse(backend.sleep)
        XCTAssertEqual(coordinator.handle(.init(.status), owner: owner).reason, .battery)
        XCTAssertTrue(coordinator.handle(.init(.configure, configuration: .init(fan: .init(mode: .maximum))), owner: owner).active)
    }

    func testThermalCutoffAndCurveSensorLossRestore() {
        let journal = Journal(), owner = UUID()
        let backend = Backend(journal)
        let coordinator = HardwareCoordinator(backend: backend, journal: journal, now: { 1 })
        _ = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner)
        backend.reading.thermalSeverity = 2; coordinator.tick()
        XCTAssertFalse(backend.sleep)
        XCTAssertEqual(coordinator.handle(.init(.status), owner: owner).reason, .thermal)
        backend.reading.thermalSeverity = 0
        XCTAssertTrue(coordinator.handle(.init(.configure, configuration: .init(fan: .init(mode: .curve))), owner: owner).active)
        backend.reading.temperatureAge = 11; coordinator.tick()
        XCTAssertTrue(backend.targets.isEmpty)
        XCTAssertEqual(coordinator.handle(.init(.status), owner: owner).reason, .sensor)
    }

    func testSeriousPressureRaisesStandaloneCoolingAndCriticalReturnsSystem() {
        let journal = Journal(), owner = UUID()
        let backend = Backend(journal)
        let coordinator = HardwareCoordinator(backend: backend, journal: journal, now: { 1 })
        _ = coordinator.handle(.init(.configure, configuration: .init(fan: .init(mode: .fixed, targets: [0: 1500]))), owner: owner)
        backend.reading.thermalSeverity = 2; coordinator.tick()
        XCTAssertEqual(backend.targets, [0: 6000])
        backend.reading.thermalSeverity = 3; coordinator.tick()
        XCTAssertTrue(backend.targets.isEmpty)
    }

    func testFailedPartialTakeoverRollsBackAndRetainsFailedRestorationForRetry() {
        let journal = Journal(), owner = UUID()
        let backend = Backend(journal)
        backend.rejectFanWrite = true; backend.rejectRestore = true
        let coordinator = HardwareCoordinator(backend: backend, journal: journal, now: { 1 })
        let status = coordinator.handle(.init(.configure, configuration: .init(lid: true,
            fan: .init(mode: .maximum))), owner: owner)
        XCTAssertFalse(status.active); XCTAssertTrue(status.restorationPending)
        XCTAssertNotNil(journal.record); XCTAssertTrue(journal.locked)
        backend.rejectRestore = false; coordinator.tick()
        XCTAssertNil(journal.record); XCTAssertFalse(backend.sleep); XCTAssertTrue(backend.targets.isEmpty)
        XCTAssertFalse(journal.locked)
    }

    func testHelperRestartRecoversBeforeAcceptingANewOwner() {
        let journal = Journal(), owner = UUID()
        let backend = Backend(journal)
        journal.record = HardwareRecovery(sleepDisabledBefore: false, fans: [0])
        backend.sleep = true; backend.targets = [0: 3000]
        let coordinator = HardwareCoordinator(backend: backend, journal: journal, now: { 1 })
        coordinator.recoverAtLaunch()
        XCTAssertFalse(backend.sleep); XCTAssertTrue(backend.targets.isEmpty); XCTAssertNil(journal.record)
        XCTAssertTrue(coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner).active)
    }

    func testAnotherConnectionAndAnotherServiceCannotStealOwnership() {
        let journal = Journal(), owner = UUID()
        let backend = Backend(journal)
        let coordinator = HardwareCoordinator(backend: backend, journal: journal, now: { 1 })
        _ = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner)
        let stranger = UUID(), count = backend.writes
        XCTAssertEqual(coordinator.handle(.init(.stop), owner: stranger).reason, .busy)
        XCTAssertEqual(coordinator.handle(.init(.renew), owner: stranger).reason, .busy)
        XCTAssertEqual(backend.writes, count); XCTAssertTrue(backend.sleep)
        coordinator.disconnect(owner: owner); XCTAssertFalse(backend.sleep)
        journal.rejectLock = true
        XCTAssertFalse(coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: stranger).active)
        XCTAssertFalse(backend.sleep)
    }

    func testUnknownPowerStateOrForeignSleepOverrideNeverClaimsSuccess() {
        for condition in 0..<4 {
            let journal = Journal()
            let actual = Backend(journal)
            if condition == 0 { actual.rejectSleepRead = true }
            if condition == 1 { actual.sleep = true }
            if condition == 2 { actual.reading.onBattery = nil }
            if condition == 3 { actual.reading.lidClosed = nil }
            let coordinator = HardwareCoordinator(backend: actual, journal: journal, now: { 1 })
            XCTAssertFalse(coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: UUID()).active)
            XCTAssertEqual(actual.writes, 0)
        }
    }

    func testMaintenanceCannotStopAnotherOwnersLiveOverride() {
        let journal = Journal(), owner = UUID()
        let actual = Backend(journal)
        let coordinator = HardwareCoordinator(backend: actual, journal: journal, now: { 1 })
        _ = coordinator.handle(.init(.configure, configuration: .init(lid: true)), owner: owner)
        let writes = actual.writes
        let denied = coordinator.handle(.init(.prepareUpdate, transaction: UUID()), owner: UUID(), user: 501)
        XCTAssertEqual(denied.reason, .busy); XCTAssertFalse(denied.maintenance)
        XCTAssertTrue(actual.sleep); XCTAssertNotNil(journal.record?.sleepDisabledBefore)
        XCTAssertEqual(actual.writes, writes)
    }

    func testDurableMaintenanceBlocksRearmAfterRestartAndDoesNotHoldAnotherVariantsLock() {
        var time: Double = 1
        let storage = Journal.Storage(), owner = UUID(), id = UUID()
        let journal = Journal(storage: storage)
        let actual = Backend(journal)
        let coordinator = HardwareCoordinator(backend: actual, journal: journal, now: { time })
        let prepared = coordinator.handle(.init(.prepareUpdate, transaction: id), owner: owner, user: 501)
        XCTAssertEqual(prepared.reason, .stopped); XCTAssertTrue(prepared.maintenance)
        XCTAssertFalse(prepared.active); XCTAssertFalse(journal.locked)
        time = 10000; coordinator.tick()
        XCTAssertEqual(storage.record?.maintenance?.transaction, id)
        let devJournal = Journal(storage: storage), devBackend = Backend(Journal())
        let dev = HardwareCoordinator(backend: devBackend, journal: devJournal,
            application: "com.antonshakirov.minimo.dev", now: { time })
        dev.recoverAtLaunch()
        XCTAssertFalse(devJournal.locked)
        XCTAssertEqual(dev.handle(.init(.configure, configuration: .init(lid: true)), owner: UUID(), user: 501).reason, .busy)
        XCTAssertEqual(storage.record?.maintenance?.transaction, id)
        XCTAssertFalse(devJournal.locked)
        let reopenedJournal = Journal(storage: storage), reopenedBackend = Backend(Journal())
        let reopened = HardwareCoordinator(backend: reopenedBackend, journal: reopenedJournal, now: { time })
        reopened.recoverAtLaunch()
        XCTAssertEqual(reopened.handle(.init(.status), owner: owner, user: 501).maintenanceID, id)
        XCTAssertEqual(reopened.handle(.init(.finishUpdate, transaction: id), owner: owner, user: 502).reason, .unauthorized)
        XCTAssertNotNil(storage.record)
        let finished = reopened.handle(.init(.finishUpdate, transaction: id), owner: owner, user: 501)
        XCTAssertEqual(finished.reason, .stopped); XCTAssertFalse(finished.maintenance)
        XCTAssertNil(storage.record)
        XCTAssertEqual(reopened.handle(.init(.finishUpdate, transaction: id), owner: owner, user: 501).reason, .stopped)
        XCTAssertEqual(actual.writes + devBackend.writes + reopenedBackend.writes, 0)
    }
}
