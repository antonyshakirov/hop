import AppKit
import Combine
import HopCore
import os

/// The VPN module: every configuration macOS knows about, with a switch and a
/// light, and — on request — the vendor's own window.
///
/// It reads and drives the system's configurations through `scutil`, the same
/// door the system's menu-bar switch uses, so ANY VPN that registers itself in
/// network settings works without support for that particular vendor and without
/// the user adding anything by hand.
///
/// The window trick (Anton, 2026-07-29): a VPN client normally sits in the Dock
/// and the menu bar all day for a switch you touch twice a week. Here the app is
/// not running at all — the tunnel is held by the system — and Hop launches it
/// only when you ask for its window, then quits it once the window is closed.
@MainActor
final class VPNController: ObservableObject {
    // nonisolated: both are read from the detached task that runs the command
    private nonisolated static let log = Logger(subsystem: "com.antonshakirov.hop", category: "VPN")
    private nonisolated static let scutil = "/usr/sbin/scutil"
    private nonisolated static let networksetup = "/usr/sbin/networksetup"
    /// How many rows are shown before the list scrolls. Three by default: most
    /// Macs have one or two configurations, and a rare fifth one should not push
    /// the modules under it off the panel.
    static let visibleRowsKey = "vpnVisibleRows"
    static let defaultVisibleRows = 3

    /// How often the tunnels are measured while there is something to measure.
    /// Counters cost microseconds, so the cadence is set by how quickly a stalled
    /// tunnel should show — not by what the reading costs.
    private static let watchInterval: TimeInterval = 2
    /// The cadence with nothing connected and the panel closed. The list still has
    /// to be re-read on its own, or a tunnel that comes up while nobody is looking
    /// would leave the menu bar showing nothing at all.
    private static let idleInterval: TimeInterval = 30

    @Published private(set) var configurations: [VPNConfiguration] = []
    /// Set while a start/stop is in flight, so the row can show it immediately
    /// rather than waiting for the next poll.
    @Published private(set) var pending: Set<String> = []
    /// The app Hop launched for its window, and is therefore responsible for
    /// closing again.
    @Published private(set) var openedApp: String?
    /// Configurations the system calls connected while nothing comes back through
    /// them.
    @Published private(set) var stalled: Set<String> = []

    private var tick: Timer?
    private var tickInterval: TimeInterval = 0
    private var windowWatch: Timer?
    /// Whether the module's own list is on screen, which is the only thing that
    /// justifies the fast cadence and a process launch per tick.
    private var panelOpen = false
    private var lastListRead = Date.distantPast
    /// Connected configuration → the interface its tunnel is on. Cached: the name
    /// cannot change without the tunnel going down first, and looking it up costs
    /// a process launch.
    private var interfaces: [String: String] = [:]
    private var liveness: [String: TunnelLiveness] = [:]

    /// Any tunnel up right now.
    var isAnyConnected: Bool { configurations.contains { $0.state.isOn } }

    /// What the menu-bar light should say, or nil while nothing is up.
    ///
    /// One stalled tunnel is enough to turn it orange even with a healthy one
    /// beside it: a tunnel is only ever called stalled while something is actively
    /// pushing bytes into it and getting nothing back, and that is broken
    /// whichever of them it is. Which one the panel says.
    var mark: VPNMark? {
        if !stalled.isEmpty { return .stalled }
        return isAnyConnected ? .up : nil
    }

    /// Whether anyone can currently see what the module has to say. With the panel
    /// closed the menu-bar dot is the only consumer, so a module that is on no
    /// space, or whose dot has been switched off, is not worth measuring — the
    /// same two conditions the icon itself is drawn under.
    private var isWatched: Bool {
        if panelOpen { return true }
        return UserDefaults.standard.bool(forKey: SettingsKey.vpnMenuBarMark)
            && !PanelView.storedModuleIsInactive("vpn")
    }

    init() {
        if Snapshot.active {
            // A screenshot of an empty list says nothing about the module. Two
            // configurations, one of them up: a client that names its country and
            // one that does not, which is exactly the pair the row layout is for.
            configurations = [
                VPNConfiguration(id: "demo-1", name: "VPN Client (Netherlands)",
                                 bundleIdentifier: nil, appName: "VPN Client", state: .connected),
                VPNConfiguration(id: "demo-2", name: "Office IKEv2",
                                 bundleIdentifier: nil, appName: nil, state: .disconnected),
            ]
            return
        }
        refresh()
        retune()
    }

    // MARK: - Reading

    /// Re-reads the list. One short command, run every tick while the panel is
    /// open and every half-minute while it is closed.
    func refresh() {
        guard !Snapshot.active else { return }
        lastListRead = Date()
        let output = Self.run([Self.scutil, "--nc", "list"])
        let fresh = VPNConfigurations.parseList(output).map(Self.named)
        // Keep a pending row on its optimistic state until the system agrees.
        configurations = fresh.map { configuration in
            guard pending.contains(configuration.id) else { return configuration }
            var settled = configuration
            if configuration.state.isBusy { return configuration }
            settled.state = configuration.state
            return settled
        }
        pending = pending.filter { id in
            fresh.first { $0.id == id }?.state.isBusy ?? false
        }
        trackInterfaces()
    }

    /// Ties every connected configuration to the interface its tunnel is on, and
    /// forgets the ones that have gone down along with whatever was known about
    /// them.
    private func trackInterfaces() {
        let up = Set(configurations.filter { $0.state.isOn }.map(\.id))
        for id in interfaces.keys where !up.contains(id) {
            interfaces[id] = nil
            liveness[id] = nil
        }
        if !stalled.isEmpty { stalled.formIntersection(up) }
        for id in up where interfaces[id] == nil {
            let status = Self.run([Self.scutil, "--nc", "status", id])
            interfaces[id] = VPNConfigurations.interfaceName(in: status)
        }
    }

    // MARK: - Measuring

    /// Reads the counters of every tracked tunnel and updates the verdicts.
    /// Returns whether an interface has gone missing, which means the list is out
    /// of date and worth re-reading ahead of its cadence.
    @discardableResult
    private func sampleTunnels() -> Bool {
        guard !interfaces.isEmpty else { return false }
        let now = Date()
        var vanished = false
        var fresh: Set<String> = []
        for (id, interface) in interfaces {
            guard let counters = InterfaceCounters.read(interface) else {
                // the tunnel took its interface down; the list will say so
                vanished = true
                liveness[id] = nil
                continue
            }
            var watch = liveness[id] ?? TunnelLiveness()
            if watch.observe(.init(inPackets: counters.inPackets,
                                   outPackets: counters.outPackets, at: now)) {
                fresh.insert(id)
            }
            liveness[id] = watch
        }
        if stalled != fresh { stalled = fresh }
        return vanished
    }

    // MARK: - The tick

    /// The module watches on its own, not only while its list is on screen: the
    /// menu-bar dot is the whole point of the light, and a dot that only updates
    /// while the panel is open says whatever was true when it last closed.
    private func fire() {
        guard isWatched else {
            // nobody can see it — drop what was being tracked and coast
            if !interfaces.isEmpty {
                interfaces.removeAll()
                liveness.removeAll()
                stalled.removeAll()
            }
            retune()
            return
        }
        let vanished = sampleTunnels()
        if panelOpen || vanished || Date().timeIntervalSince(lastListRead) >= Self.idleInterval {
            refresh()
        }
        retune()
    }

    /// Picks the cadence the current state deserves and reschedules only when it
    /// actually changes.
    private func retune() {
        guard !Snapshot.active else { return }
        let interval = (panelOpen || !interfaces.isEmpty) ? Self.watchInterval : Self.idleInterval
        guard interval != tickInterval || tick == nil else { return }
        tick?.invalidate()
        tickInterval = interval
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in self.fire() }
        }
        timer.tolerance = interval / 4
        tick = timer
    }

    func panelAppeared() {
        panelOpen = true
        refresh()
        retune()
    }

    func panelDisappeared() {
        panelOpen = false
        retune()
    }

    // MARK: - Switching

    /// Flips one configuration. `scutil` answers immediately and the tunnel comes
    /// up a moment later, so the row is marked pending until the system reports a
    /// settled state.
    func toggle(_ configuration: VPNConfiguration) {
        guard !Snapshot.active else { return }
        let turningOff = configuration.state.isOn || configuration.state.isBusy
        pending.insert(configuration.id)
        let id = configuration.id
        let name = configuration.name
        let wasEnabled = configuration.isEnabled
        // Read here rather than inside the detached work: a setting is main-actor
        // state, and this is the moment the user's choice applies.
        let holdOff = UserDefaults.standard.object(forKey: SettingsKey.vpnHoldOff) as? Bool ?? true
        // The command answers in milliseconds but blocks; off the main thread it
        // cannot stutter the panel.
        Task { [weak self] in
            await Task.detached {
                if turningOff {
                    _ = Self.run([Self.scutil, "--nc", "stop", id])
                    // A tunnel is back within seconds of being stopped — its own
                    // on-demand rules connect it again as soon as anything asks
                    // for a `.com`, and a vendor's background helper can do the
                    // same without any rules at all. Stopping is not enough: the
                    // service itself leaves the network set, which is the only
                    // lever a third-party configuration gives us. Every
                    // configuration, not only the ones we can see rules on —
                    // "off" has to mean the same thing for all of them (Anton,
                    // 2026-07-30).
                    if holdOff { Self.setService(name, enabled: false) }
                } else {
                    // Switching one back on returns it to the set first, or the
                    // start would have nothing to start.
                    if !wasEnabled { Self.setService(name, enabled: true) }
                    _ = Self.run([Self.scutil, "--nc", "start", id])
                }
            }.value
            self?.refresh()
        }
    }

    /// Switches a service on or off in the network set. `networksetup` takes the
    /// name the user sees, which is the quoted name `scutil --nc list` prints.
    private nonisolated static func setService(_ name: String, enabled: Bool) {
        _ = run([networksetup, "-setnetworkserviceenabled", name, enabled ? "on" : "off"])
    }

    // MARK: - The vendor's window

    /// Brings up the app that owns this configuration. Nothing else in Hop needs
    /// the app — this is for the times you want the vendor's own screen, to pick
    /// a country or change a setting.
    func openApp(for configuration: VPNConfiguration) {
        guard !Snapshot.active, let bundle = configuration.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        // Going to the vendor's own screen means the switch there has to work, so
        // a configuration Hop is holding out of the network set goes back in
        // first: a client that cannot connect from its own window would look
        // broken, and Hop would be the reason.
        if !configuration.isEnabled {
            let name = configuration.name
            Task { await Task.detached { Self.setService(name, enabled: true) }.value }
        }
        let options = NSWorkspace.OpenConfiguration()
        options.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: options) { [weak self] _, _ in
            Task { @MainActor in
                self?.openedApp = bundle
                self?.watchForWindowClose(bundle)
            }
        }
    }

    /// Quits the app once its last window is gone.
    ///
    /// The window list comes from the window server (no permission needed — the
    /// titles and contents are never read, only the count), because an app with
    /// no windows is still a running app and there is no notification for
    /// "the user closed the last one".
    private func watchForWindowClose(_ bundle: String) {
        windowWatch?.invalidate()
        var sawAWindow = false
        var emptyTicks = 0
        var seenAt: Date?
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                guard let app = NSRunningApplication
                    .runningApplications(withBundleIdentifier: bundle).first else {
                    self.finishWatching()   // the user quit it themselves
                    return
                }
                if Self.normalWindowCount(pid: app.processIdentifier) > 0 {
                    if !sawAWindow { seenAt = Date() }
                    sawAWindow = true
                    emptyTicks = 0
                    return
                }
                // A window can blink out of the list for a tick — during a resize,
                // a sheet, the app's own startup animation — and quitting on the
                // first empty frame closed the app right after it opened (Anton,
                // 2026-07-29). Wait for three quiet ticks, and never within two
                // seconds of the window first appearing.
                guard sawAWindow, let seenAt, Date().timeIntervalSince(seenAt) > 2 else { return }
                emptyTicks += 1
                guard emptyTicks >= 3 else { return }
                app.terminate()
                self.finishWatching()
            }
        }
        timer.tolerance = 0.3
        windowWatch = timer
    }

    private func finishWatching() {
        windowWatch?.invalidate()
        windowWatch = nil
        openedApp = nil
    }

    /// Ordinary windows only: a menu-bar item and a status popover live on higher
    /// layers and must not count as "the window is still open".
    private nonisolated static func normalWindowCount(pid: pid_t) -> Int {
        let listed = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return listed.filter { window in
            (window[kCGWindowOwnerPID as String] as? pid_t) == pid
                && (window[kCGWindowLayer as String] as? Int) == 0
        }.count
    }

    /// Looks up what the owning app is called on this Mac — the localized name
    /// the user sees in Finder, not the bundle's internal one.
    private nonisolated static func named(_ configuration: VPNConfiguration) -> VPNConfiguration {
        guard let bundle = configuration.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            return configuration
        }
        var out = configuration
        out.appName = FileManager.default.displayName(atPath: url.path)
        return out
    }

    // MARK: - Running the tool

    private nonisolated static func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            log.error("scutil failed: \(error.localizedDescription, privacy: .public)")
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
