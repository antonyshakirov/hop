import AppKit
import HopHardwareKit
import ServiceManagement

// SPEC: docs/spec.md — Cooling controls and Protected lid sessions.
@MainActor
final class CoolingController: ObservableObject {
    static let shared = CoolingController()
    @Published private(set) var snapshot = HardwareStatus()
    @Published private(set) var hasReadings = false
    @Published private(set) var lastStopReason: HardwareReason?
    @Published private(set) var serviceEnabled = false
    @Published private(set) var approvalRequired = false
    @Published private(set) var busy = false
    @Published private(set) var failure: HardwareReason?
    @Published private(set) var permissionIssue: HardwarePermissionIssue?
    var lidDidStop: ((HardwareReason?) -> Void)?
    private let preview: Bool
    private let service: CoolingService
    private var desired = HardwareConfiguration()
    private var lidDeadline: Date?
    private var viewOpen = false
    private var timer: Timer?
    private var inFlight = false
    private var updating = false
    private var lastRenewal: Double = 0
    private var lastNotified: HardwareReason?
    private static let updateRegistrationKey = "hardwareUpdateTransaction"
    private static let unregisteredKey = "hardwareUpdateUnregistered"
    private var updateLock: AppProcessLock?
    private var transaction: UUID?
    private let lockFactory: () throws -> AppProcessLock
    private let persistPreferences: () -> Bool
    private var activationObserver: NSObjectProtocol?
    private var focusObserver: NSObjectProtocol?
    private var popoverObserver: NSObjectProtocol?
    private var hardwareModules: Set<String>
    private var serviceState = CoolingServiceState.unavailable
    private var connectionFailed = false
    private let openSettings: () -> Void
    private let notificationCenter: NotificationCenter

    init(preview: Bool = false, service: CoolingService? = nil, lockFactory: (() throws -> AppProcessLock)? = nil,
         persistPreferences: @escaping () -> Bool = { UserDefaults.standard.synchronize() },
         openSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() },
         notificationCenter: NotificationCenter = .default) {
        self.preview = preview
        self.openSettings = openSettings
        self.notificationCenter = notificationCenter
        hardwareModules = Self.enabledHardwareModules
        self.service = service ?? SystemCoolingService()
        self.lockFactory = lockFactory ?? { try AppProcessLock.acquire("hardware") }
        self.persistPreferences = persistPreferences
        if preview {
            hasReadings = true
            serviceEnabled = true
            snapshot.supportsControl = true
            snapshot.temperature = 67
            snapshot.fans = [.init(id: 0, rpm: 2320, minimum: 1200, maximum: 6300, manual: false),
                             .init(id: 1, rpm: 2150, minimum: 1200, maximum: 6800, manual: false)]
        } else if !Snapshot.active {
            activationObserver = notificationCenter.addObserver(forName: ModuleActivation.didChange,
                object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, !Snapshot.active else { return }
                        self.reconcilePermissions(enabledModules: Self.enabledHardwareModules,
                            requestOnEnable: UserDefaults.standard.bool(forKey: "onboardingDone"))
                        Task { await self.reconcileModules() }
                    }
                }
            focusObserver = notificationCenter.addObserver(forName: NSApplication.didBecomeActiveNotification,
                object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.checkPermissions() }
                }
            popoverObserver = notificationCenter.addObserver(forName: NSPopover.willShowNotification,
                object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.checkPermissions() }
                }
        }
    }

    deinit {
        timer?.invalidate()
        if let activationObserver { notificationCenter.removeObserver(activationObserver) }
        if let focusObserver { notificationCenter.removeObserver(focusObserver) }
        if let popoverObserver { notificationCenter.removeObserver(popoverObserver) }
    }

    var activeFanMode: FanPolicy.Mode? {
        guard hasReadings, serviceEnabled, !connectionFailed, snapshot.active,
              !snapshot.restorationPending, snapshot.policy.mode != .automatic else { return nil }
        return snapshot.policy.mode
    }

    var blocksUpdates: Bool {
        snapshot.active || snapshot.restorationPending
            || (!updating && (snapshot.reason == .busy || snapshot.maintenance || pendingTransaction != nil))
            || (busy && !updating)
    }

    var updateDiagnosticState: [String: Bool] {
        ["active": snapshot.active, "restorationPending": snapshot.restorationPending,
         "snapshotBusy": snapshot.reason == .busy, "maintenance": snapshot.maintenance,
         "pendingTransaction": pendingTransaction != nil, "busy": busy,
         "updating": updating, "inFlight": inFlight, "blocksUpdates": blocksUpdates]
    }

    private var pendingTransaction: UUID? {
        transaction ?? UserDefaults.standard.string(forKey: Self.updateRegistrationKey).flatMap(UUID.init(uuidString:))
    }

    private static var enabledHardwareModules: Set<String> {
        Set(["system", "awake"].filter { ModuleActivation.isOn($0) })
    }

    func reconcilePermissions(enabledModules: Set<String>, requestOnEnable: Bool) {
        guard !preview else { return }
        let enabled = enabledModules.intersection(["system", "awake"])
        let newlyEnabled = enabled.subtracting(hardwareModules)
        hardwareModules = enabled
        refreshServiceState()
        if requestOnEnable, !newlyEnabled.isEmpty { requestPermission() }
    }

    func checkPermissions() {
        guard !preview, !Snapshot.active, UserDefaults.standard.bool(forKey: "onboardingDone") else { return }
        reconcilePermissions(enabledModules: Self.enabledHardwareModules, requestOnEnable: false)
        if !hardwareModules.isEmpty, serviceEnabled { Task { await refresh() } }
    }

    func requestPermission() {
        guard !preview else { return }
        refreshServiceState()
        if approvalRequired { settings(); return }
        guard !busy, !updating, pendingTransaction == nil, !snapshot.maintenance else { return }
        if serviceState == .missing { install() }
        if approvalRequired { settings() }
    }

    private func updatePermissionIssue() {
        let issue: HardwarePermissionIssue?
        if hardwareModules.isEmpty {
            issue = nil
        } else if serviceState == .approval {
            issue = .approval
        } else if updating || pendingTransaction != nil || snapshot.maintenance {
            issue = nil
        } else if failure == .unsignedBuild {
            issue = .unavailable
        } else {
            switch serviceState {
            case .missing: issue = .missing
            case .approval: issue = .approval
            case .unavailable: issue = .unavailable
            case .enabled: issue = connectionFailed ? .connection : nil
            }
        }
        if permissionIssue != issue { permissionIssue = issue }
    }

    func open() {
        guard !preview else { return }
        viewOpen = true
        startTimer()
        Task { await refresh() }
    }

    func close() { viewOpen = false; stopTimerIfIdle() }

    func install() {
        guard !preview, !busy else { return }
        if pendingTransaction != nil || snapshot.maintenance {
            Task { await resumeRegistration() }; return
        }
        do {
            let lock = try lockFactory()
            defer { lock.release() }
            try service.register(); failure = nil
        }
        catch { failure = error as? HardwareReason ?? .serviceMissing }
        refreshServiceState()
        if approvalRequired { failure = .serviceApproval }
        updatePermissionIssue()
        startTimer()
        Task { await refresh() }
    }


    func apply(_ fan: FanPolicy) {
        guard !preview, !busy, !updating else { failure = .busy; return }
        guard ModuleActivation.isOn("system") || fan.mode == .automatic else { return }
        busy = true
        Task {
            defer { busy = false; stopTimerIfIdle() }
            do {
                try await waitForRequest()
                desired.fan = fan
                try await configure()
            } catch { failure = error as? HardwareReason ?? .commandFailed }
        }
    }

    func setLid(_ on: Bool, until: Date?) async throws {
        guard !preview, !updating else { throw HardwareReason.busy }
        guard pendingTransaction == nil, !snapshot.maintenance else { throw HardwareReason.busy }
        if !on { desired.lid = false }
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        while busy && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard !busy else { service.invalidate(); throw HardwareReason.busy }
        busy = true
        defer { busy = false; stopTimerIfIdle() }
        try await waitForRequest()
        if on, service.state == .missing {
            do {
                let lock = try lockFactory()
                defer { lock.release() }
                try service.register()
            }
            catch {
                refreshServiceState()
                let reason = approvalRequired ? HardwareReason.serviceApproval : error as? HardwareReason ?? .serviceMissing
                failure = reason
                if approvalRequired { settings() }
                throw reason
            }
        }
        refreshServiceState()
        guard serviceEnabled else {
            if on, approvalRequired { settings() }
            let error = approvalRequired ? HardwareReason.serviceApproval : .serviceMissing
            failure = error; throw error
        }
        desired.lid = on; lidDeadline = on ? until : nil
        do { try await configure() }
        catch { failure = error as? HardwareReason ?? .commandFailed; throw error }
    }

    private func configure() async throws {
        desired.duration = desired.lid ? lidDeadline.map { $0.timeIntervalSinceNow } : nil
        guard desired.valid else { throw HardwareReason.invalid }
        let status = try await send(.init(.configure, configuration: desired))
        guard status.reason == nil || status.reason == .stopped,
              status.active == desired.needsLease else { throw status.reason ?? HardwareReason.commandFailed }
        failure = nil
        lastRenewal = ProcessInfo.processInfo.systemUptime
        startTimer()
    }

    private func reconcileModules() async {
        guard !ModuleActivation.isOn("system"), desired.fan.mode != .automatic, !updating else { return }
        desired.fan = .init()
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        while busy && ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard !busy else { service.invalidate(); failure = .restoreFailed; return }
        busy = true
        defer { busy = false; stopTimerIfIdle() }
        do { try await waitForRequest(); try await configure() }
        catch { failure = error as? HardwareReason ?? .commandFailed }
    }

    private func send(_ request: HardwareRequest) async throws -> HardwareStatus {
        guard !inFlight else { throw HardwareReason.busy }
        inFlight = true
        defer { inFlight = false }
        do {
            let status = try await service.request(request)
            connectionFailed = false
            accept(status)
            updatePermissionIssue()
            return status
        } catch {
            connectionFailed = true
            updatePermissionIssue()
            if snapshot.active || snapshot.restorationPending {
                snapshot.active = false; snapshot.restorationPending = true
            }
            service.invalidate()
            throw error
        }
    }

    private func waitForRequest() async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 9
        while inFlight && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard !inFlight else { service.invalidate(); throw HardwareReason.commandFailed }
    }

    private func accept(_ status: HardwareStatus) {
        let wasLid = snapshot.lid
        let wasActive = snapshot.active || snapshot.restorationPending
        snapshot = status
        hasReadings = true
        if status.active { lastStopReason = nil }
        else if wasActive { lastStopReason = status.reason == .stopped ? nil : status.reason }
        if status.reason != .busy, failure == .busy || failure == .serviceApproval || failure == .serviceMissing {
            failure = nil
        }
        if wasLid, !status.lid {
            desired.lid = false; lidDeadline = nil
            lidDidStop?(status.reason)
        }
        if !status.active {
            desired = .init(); lidDeadline = nil
            if wasActive, let reason = status.reason, reason != .stopped,
               reason != lastNotified, !preview, !Snapshot.active {
                lastNotified = reason
                Alerts.noticeIfAllowed(title: L10n.t(.coolingTitle, L10n.current),
                    body: L10n.t(CoolingCopy.key(reason), L10n.current))
            }
        }
    }

    private func refreshServiceState() {
        serviceState = service.state
        serviceEnabled = serviceState == .enabled
        approvalRequired = serviceState == .approval
        updatePermissionIssue()
    }

    func refresh() async {
        guard !preview, !busy, !inFlight, !updating else { return }
        if pendingTransaction != nil || snapshot.maintenanceID != nil { await resumeRegistration(); return }
        if !viewOpen, snapshot.active, ProcessInfo.processInfo.systemUptime - lastRenewal < 20 { return }
        refreshServiceState()
        do {
            if serviceEnabled {
                let renew = snapshot.active && desired.needsLease
                    && ProcessInfo.processInfo.systemUptime - lastRenewal >= 20
                _ = try await send(.init(renew ? .renew : .status))
                if renew { lastRenewal = ProcessInfo.processInfo.systemUptime }
            } else {
                var local = await service.localStatus()
                if snapshot.active || snapshot.restorationPending {
                    local.restorationPending = true; local.lid = snapshot.lid
                    local.reason = .restoreFailed
                }
                snapshot = local
                hasReadings = true
            }
        } catch { failure = error as? HardwareReason ?? .commandFailed }
        stopTimerIfIdle()
    }

    private func startTimer() {
        guard timer == nil, !preview else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimerIfIdle() {
        if !viewOpen && !snapshot.active && !snapshot.restorationPending && !busy
            && snapshot.reason != .busy && !snapshot.maintenance && pendingTransaction == nil {
            timer?.invalidate(); timer = nil
        }
    }

    func prepareUpdate() async throws {
        guard !blocksUpdates else { throw HardwareReason.busy }
        updating = true; busy = true
        do {
            if updateLock == nil { updateLock = try lockFactory() }
            try await waitForRequest()
            if service.state == .approval { throw HardwareReason.serviceApproval }
            if service.state == .enabled {
                let id = UUID()
                try storeTransaction(id, unregistered: false)
                let status = try await send(.init(.prepareUpdate, transaction: id))
                guard status.reason == .stopped, !status.active, !status.restorationPending, status.maintenance
                else {
                    if status.reason == .busy { clearTransaction() }
                    throw status.reason ?? HardwareReason.commandFailed
                }
                try await service.unregister()
                try storeTransaction(id, unregistered: true)
                refreshServiceState()
            }
        } catch {
            updating = false; busy = false
            if pendingTransaction == nil { updateLock?.release(); updateLock = nil }
            startTimer()
            throw error
        }
    }

    func resumeRegistration() async {
        guard !preview else { return }
        guard let id = pendingTransaction ?? snapshot.maintenanceID else {
            updating = false; busy = false
            updateLock?.release(); updateLock = nil
            return
        }
        updating = true; busy = true
        do {
            if updateLock == nil { updateLock = try lockFactory() }
            try await waitForRequest()
            try storeTransaction(id, unregistered: UserDefaults.standard.bool(forKey: Self.unregisteredKey))
            if service.state == .missing { try service.register() }
            guard service.state == .enabled else { throw HardwareReason.serviceApproval }
            if !UserDefaults.standard.bool(forKey: Self.unregisteredKey) {
                let status = try await send(.init(.prepareUpdate, transaction: id))
                guard status.reason == .stopped, !status.active, !status.restorationPending, status.maintenance
                else {
                    if status.reason == .busy { clearTransaction() }
                    throw status.reason ?? HardwareReason.commandFailed
                }
                try await service.unregister()
                try storeTransaction(id, unregistered: true)
                try service.register()
            }
            refreshServiceState()
            guard serviceEnabled else { throw HardwareReason.serviceApproval }
            let status = try await send(.init(.finishUpdate, transaction: id))
            guard status.reason == .stopped, !status.active, !status.restorationPending, !status.maintenance
            else { throw status.reason ?? HardwareReason.commandFailed }
            clearTransaction()
            failure = nil
            updateLock?.release(); updateLock = nil
        } catch { failure = error as? HardwareReason ?? .serviceMissing }
        updating = false; busy = false
        refreshServiceState()
        startTimer(); stopTimerIfIdle()
    }

    private func storeTransaction(_ id: UUID, unregistered: Bool) throws {
        let oldID = UserDefaults.standard.object(forKey: Self.updateRegistrationKey)
        let oldPhase = UserDefaults.standard.object(forKey: Self.unregisteredKey)
        UserDefaults.standard.set(id.uuidString, forKey: Self.updateRegistrationKey)
        UserDefaults.standard.set(unregistered, forKey: Self.unregisteredKey)
        guard persistPreferences() else {
            if let oldID { UserDefaults.standard.set(oldID, forKey: Self.updateRegistrationKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.updateRegistrationKey) }
            if let oldPhase { UserDefaults.standard.set(oldPhase, forKey: Self.unregisteredKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.unregisteredKey) }
            throw HardwareReason.commandFailed
        }
        transaction = id
    }

    private func clearTransaction() {
        transaction = nil
        UserDefaults.standard.removeObject(forKey: Self.updateRegistrationKey)
        UserDefaults.standard.removeObject(forKey: Self.unregisteredKey)
        _ = persistPreferences()
    }

    func settings() { guard !preview else { return }; openSettings() }
}
