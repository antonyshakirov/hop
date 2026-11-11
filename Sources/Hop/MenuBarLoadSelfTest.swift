#if DEBUG
import AppKit
import Darwin
import HopCore
import SwiftUI

@MainActor
enum MenuBarLoadSelfTest {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--menubar-load-selftest") else { return }
        guard Bundle.isDevBuild else { exit(1) }
        let results = measure()
        let passed = results.allSatisfy { $0.cpu < $0.limit }
        let report: [String: Any] = ["status": passed ? "passed" : "failed", "fixture": "offscreen synthetic model",
            "states": results.map { ["state": $0.name, "cpuPercent": $0.cpu, "limitPercent": $0.limit] }]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        exit(passed ? 0 : 1)
    }

    private static func measure() -> [(name: String, cpu: Double, limit: Double)] {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.menuBarReadings, SettingsKey.menuBarIconOnly,
                    SettingsKey.showMenuBarCountdown, SettingsKey.panelTabs]
        let saved = keys.map { defaults.object(forKey: $0) }
        let snapshot = Snapshot.active
        Snapshot.active = true
        defer {
            Snapshot.active = snapshot
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        defaults.set(true, forKey: SettingsKey.menuBarIconOnly)
        defaults.set(true, forKey: SettingsKey.showMenuBarCountdown)
        let model = AppModel(preview: true)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        defer { model.engine.reset(); model.soundCallMix.shutdown(); NSStatusBar.system.removeStatusItem(item) }
        let controller = StatusItemController(model: model, statusItem: item)
        controller.refreshButton()
        var results: [(name: String, cpu: Double, limit: Double)] = []
        results.append(("idle", cpuOverInterval(), 1))

        var config = MenuBarReadings()
        config.enabled = Set(MenuBarMetric.allCases.filter { $0 != .timer && $0 != .tracker })
        defaults.set(config.encoded, forKey: SettingsKey.menuBarReadings)
        defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
        model.engine.onFinish = nil
        model.engine.start()
        controller.refreshButton()
        results.append(("all readings, panel closed", cpuOverInterval(), 2))

        let host = NSHostingView(rootView: PanelView(initial: .spaceContaining("system"))
            .environmentObject(model).frame(width: 368))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        model.setPanelVisible(true, surface: "menu-bar-load")
        controller.freezeMenuBarReadings()
        results.append(("offscreen panel", cpuOverInterval(), 5))
        controller.thawMenuBarReadings()
        model.setPanelVisible(false, surface: "menu-bar-load")
        return results
    }

    private static func cpuOverInterval() -> Double {
        func cpuTime() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        let startCPU = cpuTime()
        let started = ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime - started < 60 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        return (cpuTime() - startCPU) / (ProcessInfo.processInfo.systemUptime - started) * 100
    }
}
#endif
