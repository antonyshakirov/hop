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
    var sleep = false
    var targets: [Int: Double] = [:]
    var reading = HardwareObservation(fans: [.init(id: 0, rpm: 1200, minimum: 1000, maximum: 6000, manual: false)],
        temperature: 70, supportsControl: true, lidClosed: false, onBattery: false, batteryPercent: 80)
    func observe() -> HardwareObservation { reading }
    func sleepDisabled() throws -> Bool { sleep }
    func setSleepDisabled(_ disabled: Bool) throws { sleep = disabled }
    func restoreClosedLidBehavior() throws {}
    func setFans(_ targets: [Int: Double]) throws { self.targets = targets }
    func restoreFans(_ indices: [Int]) throws { for index in indices { targets[index] = nil } }
}

@MainActor
private final class ClientService: CoolingService {
    var state = CoolingServiceState.enabled
    let journal = ClientJournal()
    let hardware = ClientHardware()
    var root: HardwareCoordinator
    var owner = UUID()
    var calls: [HardwareRequest.Operation] = []
    var registrationAttempts = 0
    var unregisterAttempts = 0
    var failUnregister = false
    var approvalOnRegister = false
    var failRequests = false
    init() { root = HardwareCoordinator(backend: hardware, journal: journal, now: { 1 }) }
    func register() throws {
        registrationAttempts += 1
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
        return root.handle(request, owner: owner)
    }
    func localStatus() async -> HardwareStatus {
        var status = HardwareStatus(); status.fans = hardware.reading.fans
        status.supportsControl = true; return status
    }
    func invalidate() { root.disconnect(owner: owner) }
}

@MainActor
final class CoolingControllerTests: XCTestCase {
    func testInitialAdministratorApprovalIsReportedWithoutChangingSleep() async throws {
        let (controller, service) = try fixture()
        service.state = .missing
        service.approvalOnRegister = true
        controller.install()
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
        XCTAssertEqual(service.registrationAttempts, 1)
        XCTAssertEqual(controller.permissionIssue, .approval)
        controller.reconcilePermissions(enabledModules: ["system"], requestOnEnable: true)
        controller.reconcilePermissions(enabledModules: ["system", "clipboard"], requestOnEnable: true)
        XCTAssertEqual(service.registrationAttempts, 1)
        XCTAssertTrue(service.calls.isEmpty)
        XCTAssertFalse(service.hardware.sleep)
        XCTAssertTrue(service.hardware.targets.isEmpty)
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
        service.failRequests = false
        await controller.refresh()
        XCTAssertNil(controller.permissionIssue)
        XCTAssertFalse(service.calls.contains(.configure))
    }

    func testPendingApprovalOpensSettingsOnlyForANewEnableRequest() throws {
        var settingsOpened = 0
        let (controller, service) = try fixture(openSettings: { settingsOpened += 1 })
        service.state = .approval
        controller.reconcilePermissions(enabledModules: [], requestOnEnable: false)
        controller.reconcilePermissions(enabledModules: ["awake"], requestOnEnable: false)
        XCTAssertEqual(settingsOpened, 0)
        controller.reconcilePermissions(enabledModules: [], requestOnEnable: true)
        controller.reconcilePermissions(enabledModules: ["awake"], requestOnEnable: true)
        XCTAssertEqual(settingsOpened, 1)
        controller.reconcilePermissions(enabledModules: ["awake", "clipboard"], requestOnEnable: true)
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

    private func fixture(persistenceSucceeds: Bool = true, openSettings: @escaping () -> Void = {},
                         observing: NotificationCenter? = nil) throws -> (CoolingController, ClientService) {
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
            notificationCenter: observing ?? .default)
        addTeardownBlock { @MainActor in
            controller.close(); service.invalidate()
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
