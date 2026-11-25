import AppKit
import HopHardwareKit
import ServiceManagement

// SPEC: docs/spec.md — Cooling controls and Protected lid sessions.
@MainActor
final class CoolingController: ObservableObject {
    static let shared = CoolingController(napGuard: AppNapGuard(reason: "Hop — hardware lease"))
    @Published private(set) var snapshot = HardwareStatus() {
        didSet { napGuard?.hold(snapshot.active || snapshot.restorationPending) }
    }
    @Published private(set) var hasReadings = false
    @Published private(set) var lastStopReason: HardwareReason?
    @Published private(set) var serviceEnabled = false
    @Published private(set) var approvalRequired = false
    @Published private(set) var busy = false
    @Published private(set) var pendingFanPolicy: FanPolicy?
    @Published private(set) var failure: HardwareReason?
    @Published private(set) var permissionIssue: HardwarePermissionIssue?
    var lidDidStop: ((HardwareReason?) -> Void)?
    private let preview: Bool
    private let service: CoolingService
    /// A napped app misses the lease renewal and the service ends fans and lid.
    private let napGuard: AppNapGuard?
    private var desired = HardwareConfiguration()
    private var lidDeadline: Date?
    private var viewOpen = false
    private var timer: Timer?
    private var inFlight = false
    private var updating = false
    private var lastRenewal: Double = 0
    private var fanTask: Task<Void, Never>?
    private var fanRevision: UInt64 = 0
    private var lidRevision: UInt64 = 0
    @Published private(set) var pendingLidTarget: Bool?
    private var fanReadyAt: Double = 0
    private(set) var lastFanRequest: FanPolicy?
    private var snapshotRevision: UInt64 = 0
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
    private var stateTicket: UInt64 = 0
    private var refreshing = false
    private var connectionFailed = false
    private var releasePending = false
    private let openSettings: () -> Void
    private let notificationCenter: NotificationCenter

    init(preview: Bool = false, service: CoolingService? = nil, lockFactory: (() throws -> AppProcessLock)? = nil,
         persistPreferences: @escaping () -> Bool = { UserDefaults.standard.synchronize() },
         openSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() },
         notificationCenter: NotificationCenter = .default,
         napGuard: AppNapGuard? = nil) {
        self.preview = preview
        self.napGuard = preview ? nil : napGuard
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

    var fanAvailability: FanAvailability {
        if !snapshot.fans.isEmpty { return snapshot.supportsControl ? .controllable : .unsupported }
        if let availability = snapshot.fanAvailability {
            return availability == .controllable ? .unavailable : availability
        }
        return FanDevice.isKnownFanless(FanDevice.modelIdentifier) ? .fanless : .unavailable
    }

    var needsFanServiceUpdate: Bool {
        serviceEnabled && hasReadings && snapshot.fanControlRevision != FanControlSupport.revision
    }

    var confirmedFanMode: FanPolicy.Mode? {
        guard hasReadings, snapshot.supportsControl, !snapshot.fans.isEmpty,
              !snapshot.restorationPending, !connectionFailed else { return nil }
        if snapshot.active, snapshot.policy.mode != .automatic {
            return snapshot.fans.allSatisfy(\.manual) ? snapshot.policy.mode : nil
        }
        return snapshot.fans.contains(where: \.manual) ? nil : .automatic
    }

    // SPEC: docs/spec.md — Cooling controls, the selected mode follows the click.
    var shownFanMode: FanPolicy.Mode? { pendingFanPolicy?.mode ?? confirmedFanMode }

    var activeFanMode: FanPolicy.Mode? {
        guard hasReadings, snapshot.supportsControl, serviceEnabled, !connectionFailed, snapshot.active,
              !snapshot.restorationPending, snapshot.policy.mode != .automatic else { return nil }
        return snapshot.fans.isEmpty || !snapshot.fans.allSatisfy(\.manual) ? nil : snapshot.policy.mode
    }

    var blocksUpdates: Bool {
        snapshot.active || snapshot.restorationPending || pendingFanPolicy != nil || pendingLidTarget != nil
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
        guard !hardwareModules.isEmpty else { return }
        Task {
            if await readServiceState() == .enabled { await refresh() }
        }
    }

    func requestPermission() {
        guard !preview else { return }
        Task { await askForPermission() }
    }

    private func askForPermission() async {
        let state = await readServiceState()
        if state == .approval { settings(); return }
        guard !busy, !updating, pendingTransaction == nil, !snapshot.maintenance else { return }
        if state == .missing {
            busy = true
            await runInstall()
        }
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

    func updateFanService() async {
        do { try await prepareUpdate(); await resumeRegistration() }
        catch { failure = error as? HardwareReason ?? .commandFailed }
    }

    func diagnosticKeys() async -> [FanKeyReading] { await service.localDiagnostics() }

    func diagnosticReadings() async -> HardwareStatus {
        let local = await service.localStatus()
        var value = HardwareStatus()
        value.fans = local.fans; value.temperature = local.temperature
        value.supportsControl = local.supportsControl; value.fanAvailability = local.fanAvailability
        return value
    }

    func close() { viewOpen = false; stopTimerIfIdle() }

    // SPEC: docs/spec.md — registration runs off the main thread; the button disables on click.
    func install() {
        guard !preview, !busy else { return }
        if pendingTransaction != nil || snapshot.maintenance {
            Task { await resumeRegistration() }; return
        }
        busy = true
        Task { await runInstall() }
    }

    /// The caller has already taken `busy`; it is released before the status refresh.
    private func runInstall() async {
        do {
            let lock = try lockFactory()
            defer { lock.release() }
            try await service.register(); failure = nil
        }
        catch { failure = error as? HardwareReason ?? .serviceMissing }
        let state = await readServiceState()
        if state == .approval { failure = .serviceApproval }
        updatePermissionIssue()
        busy = false
        startTimer()
        await refresh()
    }


    func apply(_ fan: FanPolicy, debounce: Bool = false) {
        lastFanRequest = fan
        guard fan.mode == .automatic || !needsFanServiceUpdate else { failure = .protocolMismatch; return }
        guard !preview, !updating, pendingTransaction == nil, !snapshot.maintenance
        else { failure = .busy; return }
        guard ModuleActivation.isOn("system") || fan.mode == .automatic else { return }
        let firstPending = pendingFanPolicy == nil
        pendingFanPolicy = fan
        fanRevision &+= 1
        if !debounce { fanReadyAt = 0 }
        else if firstPending { fanReadyAt = ProcessInfo.processInfo.systemUptime + 0.15 }
        guard fanTask == nil else { return }
        let acquired = !busy && pendingLidTarget == nil
        if acquired { busy = true }
        fanTask = Task { [weak self] in
            guard let self else { return }
            await self.drainFanRequests(acquired: acquired)
        }
    }

    private func drainFanRequests(acquired: Bool) async {
        var ownsBusy = acquired
        defer {
            if ownsBusy { busy = false }
            fanTask = nil
            stopTimerIfIdle()
        }
        while pendingFanPolicy != nil {
            do {
                if !ownsBusy {
                    let deadline = ProcessInfo.processInfo.systemUptime + 2 * HardwareRequest.maximumReplyWait + 1
                    while (busy || pendingLidTarget != nil) && ProcessInfo.processInfo.systemUptime < deadline {
                        try await Task.sleep(nanoseconds: 20_000_000)
                    }
                    guard !busy, pendingLidTarget == nil else { throw HardwareReason.busy }
                    busy = true; ownsBusy = true
                }
                while ProcessInfo.processInfo.systemUptime < fanReadyAt {
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                try await waitForRequest()
                if pendingLidTarget != nil {
                    busy = false; ownsBusy = false
                    try await Task.sleep(nanoseconds: 20_000_000)
                    continue
                }
                guard let policy = pendingFanPolicy else { break }
                let revision = fanRevision
                if !ModuleActivation.isOn("system"), policy.mode != .automatic {
                    pendingFanPolicy = nil; break
                }
                guard !updating, pendingTransaction == nil, !snapshot.maintenance else { throw HardwareReason.busy }
                if snapshot.restorationPending, policy.mode != .automatic { throw HardwareReason.restoreFailed }
                desired.fan = policy
                do { try await configure() }
                catch { failure = error as? HardwareReason ?? .commandFailed }
                if revision == fanRevision { pendingFanPolicy = nil }
                busy = false; ownsBusy = false
                // SPEC: let a waiting lid action acquire the shared request slot between fan changes.
                if pendingFanPolicy != nil { try await Task.sleep(nanoseconds: 20_000_000) }
            } catch {
                failure = error as? HardwareReason ?? .commandFailed
                pendingFanPolicy = nil
            }
        }
    }

    func setLid(_ on: Bool, until: Date?) async throws {
        guard !preview, !updating else { throw HardwareReason.busy }
        guard pendingTransaction == nil, !snapshot.maintenance else { throw HardwareReason.busy }
        lidRevision &+= 1
        let revision = lidRevision
        pendingLidTarget = on
        defer { if revision == lidRevision { pendingLidTarget = nil; stopTimerIfIdle() } }
        if !on { desired.lid = false }
        let deadline = ProcessInfo.processInfo.systemUptime + HardwareRequest.maximumReplyWait + 1
        while busy && ProcessInfo.processInfo.systemUptime < deadline {
            guard revision == lidRevision else { throw HardwareReason.stopped }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard revision == lidRevision else { throw HardwareReason.stopped }
        guard !busy else { throw HardwareReason.busy }
        busy = true
        defer { busy = false; stopTimerIfIdle() }
        try await waitForRequest()
        guard revision == lidRevision else { throw HardwareReason.stopped }
        var current = await readServiceState()
        guard revision == lidRevision else { throw HardwareReason.stopped }
        if on, current == .missing {
            do {
                let lock = try lockFactory()
                defer { lock.release() }
                try await service.register()
            }
            catch {
                let state = await readServiceState()
                let reason = state == .approval ? HardwareReason.serviceApproval : error as? HardwareReason ?? .serviceMissing
                failure = reason
                if state == .approval { settings() }
                throw reason
            }
            current = await readServiceState()
        }
        guard current == .enabled else {
            if on, current == .approval { settings() }
            let error = current == .approval ? HardwareReason.serviceApproval : .serviceMissing
            failure = error; throw error
        }
        guard revision == lidRevision else { throw HardwareReason.stopped }
        desired.lid = on; lidDeadline = on ? until : nil
        do { try await configure() }
        catch { failure = error as? HardwareReason ?? .commandFailed; throw error }
    }

    private func configure() async throws {
        desired.duration = desired.lid ? lidDeadline.map { $0.timeIntervalSinceNow } : nil
        guard desired.valid else { throw HardwareReason.invalid }
        let requested = desired
        let status = try await send(.init(.configure, configuration: requested))
        releasePending = false
        guard status.reason == nil || status.reason == .stopped,
              status.active == requested.needsLease, status.lid == requested.lid,
              !status.active || status.policy.mode == requested.fan.mode else {
            throw status.reason ?? HardwareReason.commandFailed
        }
        if requested.fan.mode != .automatic,
           !status.supportsControl || status.fans.isEmpty || !status.fans.allSatisfy(\.manual) {
            _ = try? await send(.init(.stop))
            throw HardwareReason.commandFailed
        }
        failure = nil
        lastRenewal = ProcessInfo.processInfo.systemUptime
        startTimer()
    }

    private func reconcileModules() async {
        guard !ModuleActivation.isOn("system"), desired.fan.mode != .automatic, !updating else { return }
        desired.fan = .init()
        let deadline = ProcessInfo.processInfo.systemUptime + HardwareRequest.maximumReplyWait + 1
        while busy && ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard !busy else { abandonLease(); failure = .restoreFailed; return }
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
        let deadline = ProcessInfo.processInfo.systemUptime + HardwareRequest.maximumReplyWait + 1
        while inFlight && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard !inFlight else { abandonLease(); throw HardwareReason.commandFailed }
    }

    // SPEC: docs/spec.md — Protected lid sessions, a dropped connection keeps the lease.
    /// The service keeps a running app's lease over a dropped connection, so giving up
    /// on a stuck request queues an explicit stop for the next refresh; a newer
    /// configure replaces it.
    func abandonLease() {
        service.invalidate()
        desired = .init(); lidDeadline = nil
        releasePending = true
        startTimer()
    }

    private func accept(_ status: HardwareStatus) {
        snapshotRevision &+= 1
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

    private func applyServiceState(_ value: CoolingServiceState) {
        serviceState = value
        serviceEnabled = value == .enabled
        approvalRequired = value == .approval
        updatePermissionIssue()
    }

    /// Shows the last known state at once and re-reads it off the main thread.
    func refreshServiceState() {
        if service.stateKnown { applyServiceState(service.state) }
        Task { await readServiceState() }
    }

    @discardableResult
    private func readServiceState() async -> CoolingServiceState {
        stateTicket &+= 1
        let ticket = stateTicket
        let value = await service.readState()
        if ticket == stateTicket { applyServiceState(value) }
        return value
    }

    func refresh() async {
        guard !preview, !busy, !inFlight, !updating, !refreshing else { return }
        if pendingTransaction != nil || snapshot.maintenanceID != nil { await resumeRegistration(); return }
        if !viewOpen, snapshot.active, !releasePending,
           ProcessInfo.processInfo.systemUptime - lastRenewal < 20 { return }
        refreshing = true
        defer { refreshing = false }
        let state = await readServiceState()
        guard !busy, !inFlight, !updating else { return }
        do {
            if state == .enabled {
                if releasePending {
                    let status = try await send(.init(.stop))
                    if !status.active { releasePending = false }
                } else {
                    let renew = snapshot.active && desired.needsLease
                        && ProcessInfo.processInfo.systemUptime - lastRenewal >= 20
                    _ = try await send(.init(renew ? .renew : .status))
                    if renew { lastRenewal = ProcessInfo.processInfo.systemUptime }
                }
            } else {
                var local = await service.localStatus()
                if snapshot.active || snapshot.restorationPending {
                    local.restorationPending = true; local.lid = snapshot.lid
                    local.reason = .restoreFailed
                }
                snapshot = local
                hasReadings = true
            }
        } catch {
            failure = error as? HardwareReason ?? .commandFailed
            let revision = snapshotRevision
            let local = await service.localStatus()
            if revision == snapshotRevision, !busy, !updating {
                snapshot.fans = local.fans; snapshot.temperature = local.temperature
                snapshot.supportsControl = local.supportsControl
                snapshot.fanAvailability = local.fanAvailability
                hasReadings = true
            }
        }
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
        if !viewOpen && !snapshot.active && !snapshot.restorationPending && !busy && !releasePending
            && pendingFanPolicy == nil && pendingLidTarget == nil
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
            let state = await readServiceState()
            if state == .approval { throw HardwareReason.serviceApproval }
            if state == .enabled {
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
                await readServiceState()
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
            if await readServiceState() == .missing { try await service.register() }
            guard await readServiceState() == .enabled else { throw HardwareReason.serviceApproval }
            if !UserDefaults.standard.bool(forKey: Self.unregisteredKey) {
                let status = try await send(.init(.prepareUpdate, transaction: id))
                guard status.reason == .stopped, !status.active, !status.restorationPending, status.maintenance
                else {
                    if status.reason == .busy { clearTransaction() }
                    throw status.reason ?? HardwareReason.commandFailed
                }
                try await service.unregister()
                try storeTransaction(id, unregistered: true)
                try await service.register()
            }
            guard await readServiceState() == .enabled else { throw HardwareReason.serviceApproval }
            let status = try await send(.init(.finishUpdate, transaction: id))
            guard status.reason == .stopped, !status.active, !status.restorationPending, !status.maintenance
            else { throw status.reason ?? HardwareReason.commandFailed }
            clearTransaction()
            failure = nil
            updateLock?.release(); updateLock = nil
        } catch { failure = error as? HardwareReason ?? .serviceMissing }
        updating = false; busy = false
        await readServiceState()
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
