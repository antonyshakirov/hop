import AppKit
import Darwin
import Foundation
import HopCore
import HopHardwareKit
import XCTest
@testable import Hop

private final class ClientJournal: HardwareJournal {
    var value: HardwareRecovery?
    func acquire() throws {}
    func load() throws -> HardwareRecovery? { value }
    func save(_ record: HardwareRecovery) throws { value = record }
    func clear() throws { value = nil }
    func release() {}
}

private final class ClientHardware: HardwareBackend {
    var idleReady = false
    func idleLidReleaseReady() -> Bool { idleReady }
    var sleep = false
    var targets: [Int: Double] = [:]
    var reading = HardwareObservation(fans: [.init(id: 0, rpm: 1200, minimum: 1000, maximum: 6000, manual: false)],
        temperature: 70, supportsControl: true, lidClosed: false, onBattery: false, batteryPercent: 80)
    func observe() -> HardwareObservation { reading }
    func sleepDisabled() throws -> Bool { sleep }
    func setSleepDisabled(_ disabled: Bool) throws { sleep = disabled }
    func restoreClosedLidBehavior() throws {}
    func setFans(_ targets: [Int: Double]) throws {
        self.targets = targets
        reading.fans = reading.fans.map {
            .init(id: $0.id, rpm: $0.rpm, minimum: $0.minimum, maximum: $0.maximum, manual: true)
        }
    }
    func restoreFans(_ indices: [Int]) throws {
        for index in indices { targets[index] = nil }
        reading.fans = reading.fans.map {
            .init(id: $0.id, rpm: $0.rpm, minimum: $0.minimum, maximum: $0.maximum, manual: false)
        }
    }
}

@MainActor
private final class ClientService: CoolingService {
    var state = CoolingServiceState.enabled
    let journal = ClientJournal()
    let hardware = ClientHardware()
    var root: HardwareCoordinator
    var owner = UUID()
    var calls: [HardwareRequest.Operation] = []
    var configurations: [HardwareConfiguration] = []
    var registrationAttempts = 0
    var unregisterAttempts = 0
    var failUnregister = false
    var approvalOnRegister = false
    var failRequests = false
    var revision: Int? = FanControlSupport.revision
    var localKeys: [FanKeyReading] = []
    var holdNextConfigure = false
    var known = true
    var holdNextRead = false
    var readGate: CheckedContinuation<Void, Never>?
    var stateKnown: Bool { known }
    func readState() async -> CoolingServiceState {
        let value = state
        if holdNextRead { holdNextRead = false; await withCheckedContinuation { readGate = $0 } }
        known = true
        return value
    }
    var configureGate: CheckedContinuation<Void, Never>?
    func releaseConfigure() { let gate = configureGate; configureGate = nil; gate?.resume() }
    init() { root = HardwareCoordinator(backend: hardware, journal: journal, now: { 1 }) }
    func register() throws {
        registrationAttempts += 1
        revision = FanControlSupport.revision
        if approvalOnRegister {
            state = .approval
            throw NSError(domain: "SMAppServiceErrorDomain", code: 1)
        }
        guard state != .enabled else { throw HardwareReason.busy }
        owner = UUID()
        root = HardwareCoordinator(backend: hardware, journal: journal, now: { 1 })
        root.recoverAtLaunch()
        state = .enabled
    }
    func unregister() async throws {
        unregisterAttempts += 1
        let status = root.handle(.init(.status), owner: owner)
        guard !status.active, !status.restorationPending, status.maintenance else { throw HardwareReason.busy }
        if failUnregister { throw HardwareReason.commandFailed }
        root.shutdown(); state = .missing
    }
    func request(_ request: HardwareRequest) async throws -> HardwareStatus {
        guard state == .enabled else { throw HardwareReason.serviceApproval }
        if failRequests { throw HardwareReason.commandFailed }
        calls.append(request.operation)
        if let configuration = request.configuration { configurations.append(configuration) }
        if request.operation == .configure, holdNextConfigure {
            holdNextConfigure = false
            await withCheckedContinuation { configureGate = $0 }
        }
        var result = root.handle(request, owner: owner)
        result.fanControlRevision = revision
        return result
    }
    func localStatus() async -> HardwareStatus {
        var status = HardwareStatus(); status.fans = hardware.reading.fans
        status.supportsControl = true; return status
    }
    func localDiagnostics() async -> [FanKeyReading] { localKeys }
    /// The live helper keeps a running app's lease when its connection drops.
    func invalidate() { invalidations += 1 }
    var invalidations = 0
    func exitApp() { root.disconnect(owner: owner) }
}

@MainActor
final class CoolingControllerTests: XCTestCase {
    func testOnOffOnBehindFanControlOnlyDispatchesTheLastLidIntent() async throws {
        let (controller, service) = try fixture()
        await controller.refresh()
        service.holdNextConfigure = true
        controller.apply(.init(mode: .maximum))
        for _ in 0..<1000 where service.configureGate == nil { await Task.yield() }
        var started = 0
        var tasks: [Task<Void, Never>] = []
        for target in [true, false, true] {
            tasks.append(Task { @MainActor in
                started += 1
                do { try await controller.setLid(target, until: nil) } catch {}
            })
            for _ in 0..<1000 where started != tasks.count { await Task.yield() }
        }
        service.releaseConfigure()
        for task in tasks { await task.value }
        XCTAssertEqual(service.configurations.map(\.lid), [false, true])
        XCTAssertTrue(service.hardware.sleep)
        XCTAssertTrue(controller.snapshot.lid)
        try await controller.setLid(false, until: nil)
        controller.apply(.init(mode: .automatic))
        for _ in 0..<100 where controller.busy || controller.pendingFanPolicy != nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testANewerOffDiscardsAnOnStillQueuedBehindFanControl() async throws {
        let (controller, service) = try fixture()
        await controller.refresh()
        service.holdNextConfigure = true
        controller.apply(.init(mode: .maximum))
        for _ in 0..<100 where service.configureGate == nil { await Task.yield() }
        XCTAssertNotNil(service.configureGate)
        var onStarted = false, offStarted = false
        let on = Task { @MainActor in
            onStarted = true
            do { try await controller.setLid(true, until: nil) } catch {}
        }
        for _ in 0..<100 where !onStarted { await Task.yield() }
        let off = Task { @MainActor in
            offStarted = true
            do { try await controller.setLid(false, until: nil) } catch { XCTFail("Latest OFF failed: \(error)") }
        }
        for _ in 0..<100 where !offStarted { await Task.yield() }
        service.releaseConfigure()
        await on.value; await off.value
        XCTAssertFalse(service.configurations.contains(where: \.lid),
            "An obsolete queued ON must never reach the helper")
        XCTAssertFalse(service.hardware.sleep)
        XCTAssertFalse(controller.snapshot.lid)
        controller.apply(.init(mode: .automatic))
        for _ in 0..<100 where controller.busy || controller.pendingFanPolicy != nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testLegacyHelperCannotReceiveManualControlBeforeItsSafeUpdate() async throws {
        let (controller, service) = try fixture()
        service.revision = nil
        await controller.refresh()
        XCTAssertTrue(controller.needsFanServiceUpdate)
        controller.apply(.init(mode: .maximum))
        XCTAssertFalse(service.calls.contains(.configure))
        XCTAssertNil(controller.activeFanMode)
        await controller.updateFanService()
        XCTAssertEqual(service.unregisterAttempts, 1)
        XCTAssertEqual(service.registrationAttempts, 1)
        XCTAssertFalse(controller.needsFanServiceUpdate)
        controller.apply(.init(mode: .maximum))
        for _ in 0..<200 where controller.busy || controller.pendingFanPolicy != nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(controller.activeFanMode, .maximum)
        controller.apply(.init(mode: .automatic))
        for _ in 0..<200 where controller.busy || controller.pendingFanPolicy != nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testDiagnosticExportExcludesMaintenanceIdentifiersAndUnknownKeys() async throws {
        let (controller, service) = try fixture()
        let privateID = UUID()
        _ = service.root.handle(.init(.prepareUpdate, transaction: privateID), owner: service.owner)
        service.localKeys = [
            .init(key: "F0Ac", type: "flt ", number: 2400, readable: true),
            .init(key: "bad!", type: "ui8 ", number: 1, readable: true)
        ]
        await controller.refresh()
        let result = await controller.diagnosticData()
        let data = try XCTUnwrap(result)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("F0Ac"))
        XCTAssertFalse(text.contains("bad!"))
        XCTAssertFalse(text.contains(privateID.uuidString))
        XCTAssertFalse(text.contains("maintenanceID"))
        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertFalse(text.contains("environment"))
    }

    func testConfirmedModesAndTheMonitorBadgeRequireCurrentManualReadback() async throws {
        let (controller, service) = try fixture()
        await controller.refresh()
        controller.apply(.init(mode: .maximum))
        for _ in 0..<100 where controller.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(controller.confirmedFanMode, .maximum)
        XCTAssertEqual(controller.activeFanMode, .maximum)
        controller.open()
        defer { controller.close() }
        service.hardware.reading.supportsControl = false
        await controller.refresh()
        XCTAssertNil(controller.confirmedFanMode)
        XCTAssertNil(controller.activeFanMode)
        service.hardware.reading.supportsControl = true
        service.hardware.reading.fans = [.init(id: 0, rpm: 1200, minimum: 1000, maximum: 6000, manual: false)]
        controller.open()
        for _ in 0..<100 where controller.snapshot.fans.contains(where: \.manual) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(controller.activeFanMode)
        XCTAssertNil(controller.confirmedFanMode)
    }

    func testALidOnlyLeaseCannotConfirmMacOSWhenFanReadingsAreManual() async throws {
        let (controller, service) = try fixture()
        service.hardware.reading.fans = [.init(id: 0, rpm: 2400, minimum: 1000, maximum: 6000, manual: true)]
        try await controller.setLid(true, until: nil)
        XCTAssertTrue(controller.snapshot.active)
        XCTAssertEqual(controller.snapshot.policy.mode, .automatic)
        XCTAssertNil(controller.confirmedFanMode)
        XCTAssertNil(controller.activeFanMode)
    }

    func testAutomaticSupersedesAManualRequestAlreadyInFlight() async throws {
        let (controller, service) = try fixture()
        service.holdNextConfigure = true
        controller.apply(.init(mode: .maximum))
        for _ in 0..<1000 where service.configureGate == nil { await Task.yield() }
        XCTAssertNotNil(service.configureGate)
        controller.apply(.init(mode: .automatic))
        service.releaseConfigure()
        for _ in 0..<200 where controller.busy || controller.pendingFanPolicy != nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(controller.busy)
        XCTAssertTrue(service.hardware.targets.isEmpty)
        XCTAssertFalse(controller.snapshot.active)
        XCTAssertNil(controller.failure)
    }

    func testTheLastFixedSpeedWinsWithoutLosingFastChanges() async throws {
        let (controller, service) = try fixture()
        service.holdNextConfigure = true
        controller.apply(.init(mode: .fixed, targets: [0: 2000]))
        for _ in 0..<1000 where service.configureGate == nil { await Task.yield() }
        XCTAssertNotNil(service.configureGate)
        controller.apply(.init(mode: .fixed, targets: [0: 3000]))
        controller.apply(.init(mode: .fixed, targets: [0: 4000]))
        service.releaseConfigure()
        for _ in 0..<200 where controller.busy || controller.pendingFanPolicy != nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(controller.busy)
        XCTAssertEqual(service.hardware.targets, [0: 4000])
        XCTAssertEqual(service.calls.filter { $0 == .configure }.count, 2)
        XCTAssertNil(controller.failure)
    }

    func testIdleLidReleaseUpdatesUIWithoutRearmingWhenFanPolicyChanges() async throws {
        let (controller, service) = try fixture()
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: SettingsKey.panelTabs)
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        defer {
            if let saved { defaults.set(saved, forKey: SettingsKey.panelTabs) }
            else { defaults.removeObject(forKey: SettingsKey.panelTabs) }
        }
        var stopped = 0
        controller.lidDidStop = { _ in stopped += 1 }
        try await controller.setLid(true, until: nil)
        controller.apply(.init(mode: .maximum))
        for _ in 0..<100 where controller.busy { await Task.yield() }
        XCTAssertTrue(controller.snapshot.active)
        XCTAssertEqual(controller.snapshot.policy.mode, .maximum)
        service.hardware.reading.lidClosed = true; service.hardware.idleReady = true
        service.root.tick()
        controller.open(); await controller.refresh()
        XCTAssertFalse(controller.snapshot.lid)
        XCTAssertTrue(controller.snapshot.active)
        XCTAssertEqual(stopped, 1)
        controller.apply(.init(mode: .fixed, targets: [0: 2000]))
        for _ in 0..<100 where controller.busy { await Task.yield() }
        XCTAssertFalse(service.hardware.sleep)
        XCTAssertFalse(controller.snapshot.lid)
        XCTAssertEqual(service.hardware.targets, [0: 2000])
    }

    func testInitialAdministratorApprovalIsReportedWithoutChangingSleep() async throws {
        let (controller, service) = try fixture()
        service.state = .missing
        service.approvalOnRegister = true
        controller.install()
        XCTAssertTrue(controller.busy)
        await settle()
        XCTAssertTrue(controller.approvalRequired)
        XCTAssertEqual(controller.failure, .serviceApproval)
        XCTAssertTrue(service.calls.isEmpty)
        XCTAssertFalse(service.hardware.sleep)
        service.state = .missing
        do {
            try await controller.setLid(true, until: nil)
            XCTFail("An unapproved service cannot enable lid mode")
        } catch { XCTAssertEqual(error as? HardwareReason, .serviceApproval) }
        XCTAssertTrue(service.calls.isEmpty)
        XCTAssertFalse(service.hardware.sleep)
    }

    func testModuleEnableRequestsApprovalOnceAndNeverArmsHardware() async throws {
        let (controller, service) = try fixture()
        service.state = .missing
        service.approvalOnRegister = true
        controller.reconcilePermissions(enabledModules: [], requestOnEnable: false)
        controller.reconcilePermissions(enabledModules: ["system"], requestOnEnable: true)
        XCTAssertEqual(service.registrationAttempts, 0)
        await settle()
        XCTAssertEqual(service.registrationAttempts, 1)
        XCTAssertEqual(controller.permissionIssue, .approval)
        controller.reconcilePermissions(enabledModules: ["system"], requestOnEnable: true)
        controller.reconcilePermissions(enabledModules: ["system", "clipboard"], requestOnEnable: true)
        await settle()
        XCTAssertEqual(service.registrationAttempts, 1)
        XCTAssertTrue(service.calls.isEmpty)
        XCTAssertFalse(service.hardware.sleep)
        XCTAssertTrue(service.hardware.targets.isEmpty)
    }

    func testAnUnknownServiceStateIsNotShownAndALateReadCannotOverwriteANewerOne() async throws {
        let (controller, service) = try fixture()
        service.known = false
        service.state = .approval
        service.holdNextRead = true
        controller.refreshServiceState()
        XCTAssertFalse(controller.approvalRequired)
        for _ in 0..<50 where service.readGate == nil { await Task.yield() }
        XCTAssertNotNil(service.readGate)
        service.state = .enabled
        controller.refreshServiceState()
        await settle()
        XCTAssertTrue(controller.serviceEnabled)
        let gate = service.readGate; service.readGate = nil; gate?.resume()
        await settle()
        XCTAssertTrue(controller.serviceEnabled)
        XCTAssertFalse(controller.approvalRequired)
    }

    func testPermissionBannerTracksGrantRevocationAndModuleDisableWithoutRearming() async throws {
        let (controller, service) = try fixture()
        service.state = .approval
        controller.reconcilePermissions(enabledModules: ["awake"], requestOnEnable: false)
        XCTAssertEqual(controller.permissionIssue, .approval)
        service.state = .enabled
        await controller.refresh()
        XCTAssertNil(controller.permissionIssue)
        service.state = .approval
        await controller.refresh()
        XCTAssertEqual(controller.permissionIssue, .approval)
        controller.reconcilePermissions(enabledModules: [], requestOnEnable: false)
        XCTAssertNil(controller.permissionIssue)
        XCTAssertEqual(service.registrationAttempts, 0)
        XCTAssertFalse(service.calls.contains(.configure))
        XCTAssertFalse(service.hardware.sleep)
    }

    func testReopeningNonactivatingPopoverRechecksApprovalWithoutRegisteringOrRearming() async throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.panelTabs, "onboardingDone"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(true, forKey: "onboardingDone")
        defaults.set(PanelTabsModel(tabs: [PanelTab(icon: "house", moduleKeys: ["system", "awake"])]).encoded(),
                     forKey: SettingsKey.panelTabs)
        let notifications = NotificationCenter()
        let (controller, service) = try fixture(observing: notifications)
        service.state = .approval
        controller.checkPermissions()
        XCTAssertEqual(controller.permissionIssue, .approval)

        service.state = .enabled
        notifications.post(name: NSPopover.willShowNotification, object: NSPopover())
        for _ in 0..<3 { await Task.yield() }
        XCTAssertNil(controller.permissionIssue)
        XCTAssertTrue(controller.serviceEnabled)

        service.state = .approval
        notifications.post(name: NSPopover.willShowNotification, object: NSPopover())
        for _ in 0..<3 { await Task.yield() }
        XCTAssertEqual(controller.permissionIssue, .approval)
        XCTAssertFalse(controller.serviceEnabled)
        XCTAssertEqual(service.registrationAttempts, 0)
        XCTAssertFalse(service.calls.contains(.configure))
        XCTAssertFalse(service.hardware.sleep)
        XCTAssertTrue(service.hardware.targets.isEmpty)
    }

    func testModuleSetupDoesNotCompeteWithMaintenance() async throws {
        let (controller, service) = try fixture()
        controller.reconcilePermissions(enabledModules: [], requestOnEnable: false)
        try await controller.prepareUpdate()
        controller.reconcilePermissions(enabledModules: ["system"], requestOnEnable: true)
        XCTAssertEqual(service.registrationAttempts, 0)
        XCTAssertNotNil(service.journal.value?.maintenance)
        XCTAssertFalse(service.hardware.sleep)
    }

    func testUnavailableConnectionIsVisibleAndClearsAfterARealStatusReply() async throws {
        let (controller, service) = try fixture()
        controller.reconcilePermissions(enabledModules: ["system"], requestOnEnable: false)
        service.failRequests = true
        await controller.refresh()
        XCTAssertEqual(controller.permissionIssue, .connection)
        XCTAssertTrue(controller.hasReadings)
        XCTAssertEqual(controller.snapshot.fans.count, 1)
        XCTAssertNil(controller.activeFanMode)
        service.failRequests = false
        await controller.refresh()
        XCTAssertNil(controller.permissionIssue)
        XCTAssertFalse(service.calls.contains(.configure))
    }

    func testPendingApprovalOpensSettingsOnlyForANewEnableRequest() async throws {
        var settingsOpened = 0
        let (controller, service) = try fixture(openSettings: { settingsOpened += 1 })
        service.state = .approval
        controller.reconcilePermissions(enabledModules: [], requestOnEnable: false)
        controller.reconcilePermissions(enabledModules: ["awake"], requestOnEnable: false)
        XCTAssertEqual(settingsOpened, 0)
        controller.reconcilePermissions(enabledModules: [], requestOnEnable: true)
        controller.reconcilePermissions(enabledModules: ["awake"], requestOnEnable: true)
        await settle()
        XCTAssertEqual(settingsOpened, 1)
        controller.reconcilePermissions(enabledModules: ["awake", "clipboard"], requestOnEnable: true)
        await settle()
        XCTAssertEqual(settingsOpened, 1)
        XCTAssertEqual(service.registrationAttempts, 0)
        XCTAssertTrue(service.calls.isEmpty)
    }

    func testExplicitLidRequestOpensPendingApprovalWithoutChangingSleep() async throws {
        var settingsOpened = 0
        let (controller, service) = try fixture(openSettings: { settingsOpened += 1 })
        service.state = .approval
        do { try await controller.setLid(true, until: nil); XCTFail("Approval is required") }
        catch { XCTAssertEqual(error as? HardwareReason, .serviceApproval) }
        XCTAssertEqual(settingsOpened, 1)
        XCTAssertFalse(service.hardware.sleep)
        XCTAssertFalse(controller.snapshot.active)
        XCTAssertTrue(service.calls.isEmpty)
    }

    func testObserverDoesNotLoseFastOffOnTransitions() async throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.panelTabs, "onboardingDone"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        func modules(_ systemOn: Bool) {
            let tabs = PanelTabsModel(tabs: [PanelTab(icon: "house", moduleKeys: ["timer", "system", "awake"])],
                hidden: systemOn ? ["awake"] : ["awake", "system"])
            XCTAssertNotNil(PanelTabsModel.decode(tabs.encoded()))
            defaults.set(tabs.encoded(), forKey: SettingsKey.panelTabs)
        }
        defaults.set(true, forKey: "onboardingDone")
        modules(true)
        let notifications = NotificationCenter()
        let (controller, service) = try fixture(observing: notifications)
        service.state = .missing
        service.approvalOnRegister = true
        modules(false)
        notifications.post(name: ModuleActivation.didChange, object: nil)
        modules(true)
        notifications.post(name: ModuleActivation.didChange, object: nil)
        controller.checkPermissions()
        for _ in 0..<3 { await Task.yield() }
        XCTAssertEqual(service.registrationAttempts, 1)
        XCTAssertEqual(controller.permissionIssue, .approval)
        XCTAssertFalse(service.hardware.sleep)
    }

    func testOnboardingModuleChangesUpdateBaselineWithoutRequestingAccess() async throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.panelTabs, "onboardingDone"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(false, forKey: "onboardingDone")
        defaults.set(PanelTabsModel(tabs: [PanelTab(icon: "house", moduleKeys: ["timer", "system", "awake"])], hidden: ["system", "awake"]).encoded(), forKey: SettingsKey.panelTabs)
        let notifications = NotificationCenter()
        let (controller, service) = try fixture(observing: notifications)
        service.state = .missing
        service.approvalOnRegister = true
        defaults.set(PanelTabsModel(tabs: [PanelTab(icon: "house", moduleKeys: ["timer", "system", "awake"])], hidden: ["awake"]).encoded(), forKey: SettingsKey.panelTabs)
        XCTAssertNotNil(PanelTabsModel.decode(defaults.string(forKey: SettingsKey.panelTabs) ?? ""))
        notifications.post(name: ModuleActivation.didChange, object: nil)
        defaults.set(true, forKey: "onboardingDone")
        notifications.post(name: ModuleActivation.didChange, object: nil)
        for _ in 0..<3 { await Task.yield() }
        XCTAssertEqual(service.registrationAttempts, 0)
        XCTAssertEqual(controller.permissionIssue, .missing)
        XCTAssertFalse(service.hardware.sleep)
    }

    func testPendingUpdateApprovalKeepsBannerAndSettingsWithoutCrossingTheFence() async throws {
        var settingsOpened = 0
        let (controller, service) = try fixture(openSettings: { settingsOpened += 1 })
        controller.reconcilePermissions(enabledModules: [], requestOnEnable: false)
        try await controller.prepareUpdate()
        service.state = .approval
        controller.reconcilePermissions(enabledModules: ["system"], requestOnEnable: true)
        await settle()
        XCTAssertEqual(controller.permissionIssue, .approval)
        XCTAssertEqual(settingsOpened, 1)
        XCTAssertEqual(service.registrationAttempts, 0)
        XCTAssertNotNil(service.journal.value?.maintenance)
        XCTAssertFalse(service.hardware.sleep)
    }

    func testAnIdleStatusDoesNotClaimAnotherSessionsOldCutoffAsOurFailure() async throws {
        let (controller, service) = try fixture()
        let previous = UUID()
        _ = service.root.handle(.init(.configure, configuration: .init(lid: true)), owner: previous)
        service.root.disconnect(owner: previous)
        await controller.refresh()
        XCTAssertFalse(controller.snapshot.active)
        XCTAssertFalse(controller.snapshot.restorationPending)
        XCTAssertEqual(controller.snapshot.reason, .disconnected)
        XCTAssertNil(controller.lastStopReason)
        XCTAssertNil(controller.failure)
        XCTAssertTrue(controller.hasReadings)
    }

    /// Lets the controller's background-style tasks (install, permission request) finish.
    private func settle() async { for _ in 0..<50 { await Task.yield() } }

    private func fixture(persistenceSucceeds: Bool = true, openSettings: @escaping () -> Void = {},
                         observing: NotificationCenter? = nil,
                         napGuard: AppNapGuard? = nil) throws -> (CoolingController, ClientService) {
        let defaults = UserDefaults.standard
        let keys = ["hardwareUpdateTransaction", "hardwareUpdateUnregistered"]
        let saved = keys.map { defaults.object(forKey: $0) }
        for key in keys { defaults.removeObject(forKey: key) }
        let wasSnapshot = Snapshot.active
        Snapshot.active = observing == nil
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("client-lock-\(UUID().uuidString)")
        let service = ClientService()
        let controller = CoolingController(service: service,
            lockFactory: { try AppProcessLock(directory: directory, name: "hardware") },
            persistPreferences: { persistenceSucceeds }, openSettings: openSettings,
            notificationCenter: observing ?? .default, napGuard: napGuard)
        addTeardownBlock { @MainActor in
            controller.close(); service.exitApp()
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            Snapshot.active = wasSnapshot
            try? FileManager.default.removeItem(at: directory)
        }
        return (controller, service)
    }

    func testLidControlAndCutoffReachActualCoordinatorAndDoNotRearm() async throws {
        let (controller, service) = try fixture()
        var stopped = 0
        controller.lidDidStop = { _ in stopped += 1 }
        try await controller.setLid(true, until: nil)
        XCTAssertTrue(service.hardware.sleep); XCTAssertTrue(controller.snapshot.lid)
        XCTAssertTrue(controller.blocksUpdates)
        service.hardware.reading.onBattery = true; service.hardware.reading.batteryPercent = 10
        service.root.tick()
        controller.open()
        await controller.refresh()
        await Task.yield()
        XCTAssertFalse(service.hardware.sleep)
        XCTAssertFalse(controller.snapshot.active)
        XCTAssertEqual(stopped, 1)
        XCTAssertEqual(controller.lastStopReason, .battery)
        await controller.refresh()
        XCTAssertEqual(service.calls.filter { $0 == .configure }.count, 1)
    }

    func testATimedOutReplyAfterOpeningTheLidKeepsTheLidSession() async throws {
        let (controller, service) = try fixture()
        var stopped = 0
        controller.lidDidStop = { _ in stopped += 1 }
        try await controller.setLid(true, until: nil)
        controller.open()
        service.failRequests = true
        await controller.refresh()
        XCTAssertEqual(service.invalidations, 1)
        XCTAssertTrue(service.hardware.sleep)
        service.failRequests = false
        await controller.refresh()
        XCTAssertTrue(controller.snapshot.active); XCTAssertTrue(controller.snapshot.lid)
        XCTAssertFalse(controller.snapshot.restorationPending)
        XCTAssertEqual(stopped, 0)
        XCTAssertNil(controller.lastStopReason)
        XCTAssertTrue(service.hardware.sleep)
    }

    func testGivingUpOnAStuckRequestStopsTheKeptLeaseOnTheNextRefresh() async throws {
        let (controller, service) = try fixture()
        var stopped = 0
        controller.lidDidStop = { _ in stopped += 1 }
        try await controller.setLid(true, until: nil)
        controller.abandonLease()
        XCTAssertEqual(service.invalidations, 1)
        await controller.refresh()
        XCTAssertEqual(service.calls.last, .stop)
        XCTAssertFalse(service.hardware.sleep)
        XCTAssertFalse(controller.snapshot.active); XCTAssertFalse(controller.snapshot.lid)
        XCTAssertEqual(stopped, 1)
        await controller.refresh()
        XCTAssertEqual(service.calls.filter { $0 == .stop }.count, 1)
    }

    func testANewerLidRequestReplacesAQueuedRelease() async throws {
        let (controller, service) = try fixture()
        try await controller.setLid(true, until: nil)
        controller.abandonLease()
        try await controller.setLid(true, until: nil)
        await controller.refresh()
        XCTAssertFalse(service.calls.contains(.stop))
        XCTAssertTrue(service.hardware.sleep); XCTAssertTrue(controller.snapshot.lid)
    }

    func testALiveLeaseKeepsHopOutOfAppNapUntilTheServiceEndsIt() async throws {
        var begun = 0, ended = 0
        let napGuard = AppNapGuard(reason: "test", begin: { begun += 1; return NSObject() }, end: { _ in ended += 1 })
        let (controller, service) = try fixture(napGuard: napGuard)
        try await controller.setLid(true, until: nil)
        XCTAssertTrue(napGuard.isHeld)
        service.hardware.reading.onBattery = true; service.hardware.reading.batteryPercent = 10
        service.root.tick()
        controller.open()
        await controller.refresh()
        XCTAssertFalse(controller.snapshot.active)
        XCTAssertFalse(napGuard.isHeld)
        XCTAssertEqual(begun, 1); XCTAssertEqual(ended, 1)
    }

    func testABatteryCutoffOfTheLidLeaseLeavesAwakeRunning() async throws {
        let (controller, service) = try fixture()
        let awake = KeepAwakeController(demo: true)
        let deadline = awake.until
        awake.observeLidStops(controller)
        try await controller.setLid(true, until: nil)
        service.hardware.reading.onBattery = true; service.hardware.reading.batteryPercent = 10
        service.root.tick()
        controller.open()
        await controller.refresh()
        XCTAssertFalse(controller.snapshot.lid)
        XCTAssertTrue(awake.isActive)
        XCTAssertEqual(awake.until, deadline)
    }

    func testApprovalFailureNeverClaimsLidOrTouchesHardware() async throws {
        let (controller, service) = try fixture()
        service.state = .approval
        do { try await controller.setLid(true, until: nil); XCTFail("Approval must be required") }
        catch { XCTAssertEqual(error as? HardwareReason, .serviceApproval) }
        XCTAssertFalse(controller.snapshot.lid); XCTAssertFalse(service.hardware.sleep)
        XCTAssertTrue(service.calls.isEmpty)
    }

    func testPrepareCannotUnregisterAnotherConnectionsActiveLeaseAndBusyClearsAfterClose() async throws {
        let (controller, service) = try fixture()
        let other = UUID()
        _ = service.root.handle(.init(.configure, configuration: .init(lid: true)), owner: other)
        do { try await controller.prepareUpdate(); XCTFail("A foreign live lease must block update") }
        catch { XCTAssertEqual(error as? HardwareReason, .busy) }
        XCTAssertEqual(service.unregisterAttempts, 0)
        XCTAssertTrue(service.hardware.sleep)
        controller.close()
        _ = service.root.handle(.init(.stop), owner: other)
        await controller.refresh()
        XCTAssertFalse(controller.blocksUpdates)
    }

    func testUpdateWaitsForIdleAndCompletesDurableFenceAfterNewDaemonHandshake() async throws {
        let (controller, service) = try fixture()
        try await controller.setLid(true, until: nil)
        do { try await controller.prepareUpdate(); XCTFail("Active hardware must defer update") }
        catch { XCTAssertEqual(error as? HardwareReason, .busy) }
        XCTAssertEqual(service.unregisterAttempts, 0)
        try await controller.setLid(false, until: nil)
        try await controller.prepareUpdate()
        XCTAssertEqual(service.state, .missing)
        XCTAssertNotNil(service.journal.value?.maintenance)
        XCTAssertFalse(service.hardware.sleep)
        await controller.resumeRegistration()
        XCTAssertEqual(service.state, .enabled)
        XCTAssertNil(service.journal.value)
        XCTAssertFalse(controller.blocksUpdates)
        XCTAssertEqual(service.calls.suffix(2), [.prepareUpdate, .finishUpdate])
    }

    func testUnregisterFailureRetainsFenceAndRetryPerformsABarrierBeforeClearingIt() async throws {
        let (controller, service) = try fixture()
        service.failUnregister = true
        do { try await controller.prepareUpdate(); XCTFail("Injected unregister failure") } catch {}
        XCTAssertNotNil(service.journal.value?.maintenance)
        XCTAssertTrue(controller.blocksUpdates)
        service.failUnregister = false
        await controller.resumeRegistration()
        XCTAssertEqual(service.unregisterAttempts, 2)
        XCTAssertNil(service.journal.value)
        XCTAssertFalse(controller.blocksUpdates)
    }

    func testFailedPreferencePersistenceCannotStartMaintenanceOrUnregister() async throws {
        let (controller, service) = try fixture(persistenceSucceeds: false)
        do { try await controller.prepareUpdate(); XCTFail("Persistence must precede prepare") }
        catch { XCTAssertEqual(error as? HardwareReason, .commandFailed) }
        XCTAssertNil(service.journal.value)
        XCTAssertTrue(service.calls.isEmpty)
        XCTAssertEqual(service.unregisterAttempts, 0)
        await controller.resumeRegistration()
        await controller.refresh()
        XCTAssertNil(service.journal.value)
        XCTAssertEqual(service.unregisterAttempts, 0)
        XCTAssertFalse(service.calls.contains(.prepareUpdate))
    }
}
