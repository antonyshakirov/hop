import AppKit
import HopCore
import XCTest
@testable import Hop

@MainActor
final class MenuBarReadingTests: XCTestCase {
    func testCompactReadingsContainOnlyValuesAndUnits() {
        var sample = StatsSample()
        sample.diskFree = 167_200_000_000
        sample.memUsed = 19.9 * 1_073_741_824
        sample.memTotal = 24 * 1_073_741_824
        sample.cpuLoad = 0.24
        XCTAssertEqual(reading(.disk, sample).text, "167.2 GB")
        XCTAssertEqual(reading(.memory, sample).text, "19.9/24 GB")
        XCTAssertEqual(reading(.cpu, sample).text, "24%")
        let detailed = MenuBarReading.sensor(.disk, sample: sample, detailed: true, lang: .en, temperatureUnit: "c")
        XCTAssertTrue(detailed.text.contains("startup disk"))
        XCTAssertTrue(detailed.text.hasSuffix("167.2 GB"))
        XCTAssertEqual(reading(.memory, sample).tooltip(lang: .en).replacingOccurrences(of: "\u{00A0}", with: " "),
            "memory: 19.9 used of 24 GB")
    }

    func testExpandedHostWidthIsNotFrozenIntoTheReadings() throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.menuBarReadings, SettingsKey.menuBarIconOnly,
                    SettingsKey.showMenuBarCountdown, SettingsKey.panelTabs]
        let saved = keys.map { defaults.object(forKey: $0) }
        let snapshot = Snapshot.active
        Snapshot.active = true
        defer {
            Snapshot.active = snapshot
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
        defaults.set(false, forKey: SettingsKey.showMenuBarCountdown)
        var config = MenuBarReadings()
        config.enabled = [.gpu]
        defaults.set(config.encoded, forKey: SettingsKey.menuBarReadings)
        let model = AppModel(preview: true)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        defer { model.soundCallMix.shutdown(); NSStatusBar.system.removeStatusItem(item) }
        let controller = StatusItemController(model: model, statusItem: item)
        controller.refreshButton()
        let compactWidth = item.length
        item.length = 1200
        controller.freezeMenuBarReadings()
        model.stats.injectDemoGpu(load: 0.99, temp: nil)
        controller.refreshButton()
        XCTAssertEqual(item.length, compactWidth)
    }

    func testLabelsSwitchAlsoLabelsTheRunningClock() throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.menuBarReadings, SettingsKey.menuBarIconOnly,
                    SettingsKey.showMenuBarCountdown, SettingsKey.panelTabs, SettingsKey.appLanguage]
        let saved = keys.map { defaults.object(forKey: $0) }
        let snapshot = Snapshot.active
        Snapshot.active = true
        defer {
            Snapshot.active = snapshot
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        defaults.set("en", forKey: SettingsKey.appLanguage)
        defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
        defaults.set(true, forKey: SettingsKey.showMenuBarCountdown)
        var config = MenuBarReadings()
        config.detailed = true
        defaults.set(config.encoded, forKey: SettingsKey.menuBarReadings)
        let model = AppModel(preview: true)
        model.engine.onFinish = nil
        model.engine.start()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        defer { model.engine.reset(); model.soundCallMix.shutdown(); NSStatusBar.system.removeStatusItem(item) }
        let controller = StatusItemController(model: model, statusItem: item)
        controller.refreshButton()
        XCTAssertTrue(try XCTUnwrap(item.button).attributedTitle.string.contains("timer"))
    }

    func testMixerMarkHasAnExplicitGapBeforeReadings() throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.menuBarReadings, SettingsKey.menuBarIconOnly,
                    SettingsKey.showMenuBarCountdown, SettingsKey.soundMenuBarMark, SettingsKey.panelTabs]
        let saved = keys.map { defaults.object(forKey: $0) }
        let snapshot = Snapshot.active
        Snapshot.active = true
        defer {
            Snapshot.active = snapshot
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
        defaults.set(false, forKey: SettingsKey.showMenuBarCountdown)
        defaults.set(true, forKey: SettingsKey.soundMenuBarMark)
        var config = MenuBarReadings()
        config.enabled = [.disk]
        defaults.set(config.encoded, forKey: SettingsKey.menuBarReadings)
        let model = AppModel(preview: true)
        model.soundCallMix.stageDemo(model.soundMixer.apps)
        let mixerReading = MenuBarReading.live(.inputMix, model: model, detailed: false, lang: .en, temperatureUnit: "c")
        XCTAssertEqual(mixerReading.value, "✓")
        XCTAssertTrue(mixerReading.tooltip(lang: .en).contains("running"))
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        defer { model.soundCallMix.shutdown(); NSStatusBar.system.removeStatusItem(item) }
        let controller = StatusItemController(model: model, statusItem: item)
        controller.refreshButton()
        let button = try XCTUnwrap(item.button)
        let gap = button.attributedTitle.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat ?? 0
        XCTAssertGreaterThanOrEqual(gap, 6)
        let content = button.attributedTitle.size().width + (button.image?.size.width ?? 0)
        XCTAssertLessThanOrEqual(item.length - content, 20)
    }

    func testStorageMemoryAndNetworkUseTheirOwnUnits() {
        var sample = StatsSample()
        sample.diskFree = 128_000_000_000
        sample.memUsed = 18 * 1_073_741_824
        sample.memTotal = 32 * 1_073_741_824
        sample.netDown = 12_000_000
        XCTAssertEqual(reading(.disk, sample).value, "128.0 GB")
        XCTAssertEqual(reading(.memory, sample).value, "18.0/32 GB")
        XCTAssertEqual(reading(.download, sample).value, "12.0 MB/s")
    }

    func testUnavailableAndInvalidSensorsNeverInventZeroOrCrash() {
        for metric in MenuBarMetric.allCases where metric.module == "system" {
            XCTAssertEqual(reading(metric, StatsSample()).value, "—", metric.rawValue)
        }
        var sample = StatsSample()
        sample.cpuLoad = .nan
        sample.diskFree = .infinity
        sample.memUsed = 20
        sample.memTotal = 10
        sample.netDown = -1
        XCTAssertEqual(reading(.cpu, sample).value, "—")
        XCTAssertEqual(reading(.disk, sample).value, "—")
        XCTAssertEqual(reading(.memory, sample).value, "—")
        XCTAssertEqual(reading(.download, sample).value, "—")
    }

    func testTemperaturePreferenceAndSignedBatteryPower() {
        var sample = StatsSample()
        sample.cpuTemp = 50
        sample.battery = BatteryInfo(isCharging: false, batteryWatts: -12)
        XCTAssertEqual(MenuBarReading.sensor(.cpuTemperature, sample: sample, detailed: false,
            lang: .en, temperatureUnit: "f").value, "122°F")
        XCTAssertEqual(reading(.batteryPower, sample).value, "-12.0 W")
    }

    func testSelectedDiskActuallyAppearsAndIconOnlyKeepsPreferences() throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.menuBarReadings, SettingsKey.menuBarIconOnly,
                    SettingsKey.showMenuBarCountdown, SettingsKey.panelTabs]
        let previous = keys.map { defaults.object(forKey: $0) }
        let snapshot = Snapshot.active
        Snapshot.active = true
        defer {
            Snapshot.active = snapshot
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        var config = MenuBarReadings()
        config.enabled = [.disk]
        defaults.set(config.encoded, forKey: SettingsKey.menuBarReadings)
        defaults.set(false, forKey: SettingsKey.showMenuBarCountdown)
        defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        let model = AppModel(preview: true)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        defer { model.soundCallMix.shutdown(); NSStatusBar.system.removeStatusItem(item) }
        let controller = StatusItemController(model: model, statusItem: item)
        let button = try XCTUnwrap(item.button)
        controller.refreshButton()
        XCTAssertTrue(button.attributedTitle.string.contains("GB"))
        let initialWidth = item.length
        controller.freezeMenuBarReadings()
        config.enabled = [.disk, .cpu, .memory, .gpu]
        config.layout = .together
        defaults.set(config.encoded, forKey: SettingsKey.menuBarReadings)
        controller.refreshButton()
        XCTAssertEqual(item.length, initialWidth)
        controller.thawMenuBarReadings()
        controller.refreshButton()
        XCTAssertTrue(button.toolTip?.contains("CPU") == true)

        var tabs = PanelTabsModel.migrate(moduleOrder: ["timer", "system"])
        controller.freezeMenuBarReadings()
        tabs.setHidden("system", hidden: true)
        defaults.set(tabs.encoded(), forKey: SettingsKey.panelTabs)
        controller.refreshButton()
        XCTAssertFalse(button.toolTip?.contains("GB") == true)
        controller.thawMenuBarReadings()
        controller.refreshButton()
        XCTAssertEqual(button.title, "")
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        defaults.set(true, forKey: SettingsKey.menuBarIconOnly)
        controller.refreshButton()
        XCTAssertEqual(button.title, "")
        XCTAssertEqual(MenuBarReadings.decode(defaults.string(forKey: SettingsKey.menuBarReadings) ?? "").enabled, config.enabled)
        defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
        controller.refreshButton()
        XCTAssertTrue(button.attributedTitle.string.contains("GB"))
    }

    private func reading(_ metric: MenuBarMetric, _ sample: StatsSample) -> MenuBarReading {
        MenuBarReading.sensor(metric, sample: sample, detailed: false, lang: .en, temperatureUnit: "c")
    }

    func testVPNReadingKeepsWatchingWithoutLegacyMark() {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.menuBarReadings, SettingsKey.menuBarIconOnly,
                    SettingsKey.vpnMenuBarMark, SettingsKey.panelTabs]
        let saved = keys.map { defaults.object(forKey: $0) }
        let snapshot = Snapshot.active
        Snapshot.active = true
        defer {
            Snapshot.active = snapshot
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        defaults.set(false, forKey: SettingsKey.vpnMenuBarMark)
        defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
        var config = MenuBarReadings()
        config.enabled = [.vpn]
        defaults.set(config.encoded, forKey: SettingsKey.menuBarReadings)
        let vpn = VPNController(demo: true)
        XCTAssertTrue(vpn.isWatched)
        defaults.set(true, forKey: SettingsKey.menuBarIconOnly)
        XCTAssertFalse(vpn.isWatched)
        defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
        var tabs = PanelTabsModel.migrate(moduleOrder: ["vpn"])
        tabs.setHidden("vpn", hidden: true)
        defaults.set(tabs.encoded(), forKey: SettingsKey.panelTabs)
        XCTAssertFalse(vpn.isWatched)
    }

    func testLiveVPNStartsWithoutDemoConnectionsBeforeItsFirstRead() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: SettingsKey.panelTabs)
        let snapshot = Snapshot.active
        Snapshot.active = false
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        defer {
            Snapshot.active = snapshot
            if let previous { defaults.set(previous, forKey: SettingsKey.panelTabs) }
            else { defaults.removeObject(forKey: SettingsKey.panelTabs) }
        }
        let vpn = VPNController()
        defer {
            var tabs = PanelTabsModel.migrate(moduleOrder: ["vpn"])
            tabs.setHidden("vpn", hidden: true)
            defaults.set(tabs.encoded(), forKey: SettingsKey.panelTabs)
            vpn.applyActivation()
        }
        XCTAssertTrue(vpn.configurations.isEmpty)
        XCTAssertNil(vpn.mark)
    }

    func testValueChangesDoNotChangeFrozenAutomaticRotation() throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.menuBarReadings, SettingsKey.menuBarIconOnly,
                    SettingsKey.showMenuBarCountdown, SettingsKey.panelTabs, SettingsKey.appLanguage]
        let saved = keys.map { defaults.object(forKey: $0) }
        let snapshot = Snapshot.active
        Snapshot.active = true
        defer {
            Snapshot.active = snapshot
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        defaults.set("en", forKey: SettingsKey.appLanguage)
        defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
        defaults.set(false, forKey: SettingsKey.showMenuBarCountdown)
        let model = AppModel(preview: true)
        model.stats.injectDemoGpu(load: 1, temp: nil)
        let extras: [MenuBarMetric] = [.cpu, .memory, .swap, .disk, .download, .upload, .battery, .batteryPower, .adapterPower, .uptime]
        var config = MenuBarReadings()
        config.layout = .together
        config.detailed = true
        let match = (0..<(1 << extras.count)).first { mask in
            let metrics = [.gpu] + extras.enumerated().compactMap { mask & (1 << $0.offset) != 0 ? $0.element : nil }
            let texts = metrics.map { MenuBarReading.live($0, model: model, detailed: true, lang: .en, temperatureUnit: "c").text }
            let length = texts.joined(separator: "  ").count
            return (55...56).contains(length)
        }
        let mask = try XCTUnwrap(match)
        config.enabled = Set([.gpu] + extras.enumerated().compactMap { mask & (1 << $0.offset) != 0 ? $0.element : nil })
        defaults.set(config.encoded, forKey: SettingsKey.menuBarReadings)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        defer { model.soundCallMix.shutdown(); NSStatusBar.system.removeStatusItem(item) }
        let controller = StatusItemController(model: model, statusItem: item)
        let button = try XCTUnwrap(item.button)
        controller.refreshButton()
        XCTAssertTrue(button.attributedTitle.string.contains("\u{FFFC}"))
        let width = item.length
        controller.freezeMenuBarReadings()
        model.stats.injectDemoGpu(load: 0, temp: nil)
        controller.refreshButton()
        XCTAssertEqual(item.length, width)
        XCTAssertTrue(button.attributedTitle.string.contains("\u{FFFC}"))
        controller.thawMenuBarReadings()
        controller.refreshButton()
        XCTAssertFalse(button.attributedTitle.string.contains("\u{FFFC}"))
    }

    func testWideLocalizedGlyphsRotateBeforeTheBarClipsThem() throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.menuBarReadings, SettingsKey.menuBarIconOnly,
                    SettingsKey.showMenuBarCountdown, SettingsKey.panelTabs, SettingsKey.appLanguage]
        let saved = keys.map { defaults.object(forKey: $0) }
        let snapshot = Snapshot.active
        Snapshot.active = true
        defer {
            Snapshot.active = snapshot
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        defaults.set("zh", forKey: SettingsKey.appLanguage)
        defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
        defaults.set(false, forKey: SettingsKey.showMenuBarCountdown)
        let model = AppModel(preview: true)
        let metrics: [MenuBarMetric] = [.cpu, .gpu, .memory, .swap, .disk, .download, .upload, .battery, .batteryHealth, .batteryCycles]
        let texts = metrics.map { MenuBarReading.live($0, model: model, detailed: true, lang: .zh, temperatureUnit: "c").text }
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let mask = try XCTUnwrap((1..<(1 << metrics.count)).first { mask in
            let text = texts.enumerated().compactMap { mask & (1 << $0.offset) != 0 ? $0.element : nil }.joined(separator: "  ")
            return text.count <= 54 && (text as NSString).size(withAttributes: [.font: font]).width > 420
        })
        var config = MenuBarReadings()
        config.layout = .together
        config.detailed = true
        config.enabled = Set(metrics.enumerated().compactMap { mask & (1 << $0.offset) != 0 ? $0.element : nil })
        defaults.set(config.encoded, forKey: SettingsKey.menuBarReadings)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        defer { model.soundCallMix.shutdown(); NSStatusBar.system.removeStatusItem(item) }
        let controller = StatusItemController(model: model, statusItem: item)
        controller.refreshButton()
        XCTAssertTrue(try XCTUnwrap(item.button).attributedTitle.string.contains("\u{FFFC}"))
    }
}
