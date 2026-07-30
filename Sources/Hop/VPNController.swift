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

    @Published private(set) var configurations: [VPNConfiguration] = []
    /// Set while a start/stop is in flight, so the row can show it immediately
    /// rather than waiting for the next poll.
    @Published private(set) var pending: Set<String> = []
    /// The app Hop launched for its window, and is therefore responsible for
    /// closing again.
    @Published private(set) var openedApp: String?

    private var poll: Timer?
    private var windowWatch: Timer?

    /// Any tunnel up right now — what the panel's green dot keys off.
    var isAnyConnected: Bool { configurations.contains { $0.state.isOn } }

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
    }

    // MARK: - Reading

    /// Re-reads the list. Cheap enough to run while the panel is open (one short
    /// command), and stopped as soon as it closes.
    func refresh() {
        guard !Snapshot.active else { return }
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
    }

    func startPolling() {
        guard !Snapshot.active, poll == nil else { return }
        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
        timer.tolerance = 0.5
        poll = timer
    }

    func stopPolling() {
        poll?.invalidate()
        poll = nil
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
                    // A tunnel with on-demand rules is back within seconds — the
                    // rules connect it again as soon as anything asks for a
                    // `.com` (Anton, 2026-07-30). Stopping it is not enough; the
                    // service itself has to leave the network set, which is the
                    // only lever a third-party configuration gives us.
                    if holdOff, Self.reconnectsByItself(id) {
                        Self.setService(name, enabled: false)
                    }
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

    /// Whether this configuration has on-demand rules, which is what makes a
    /// stopped tunnel come back on its own.
    private nonisolated static func reconnectsByItself(_ id: String) -> Bool {
        run([scutil, "--nc", "show", id]).contains("OnDemandEnabled : TRUE")
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
