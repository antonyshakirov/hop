import AppKit
import HopCore
import HopHardwareKit
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class CoolingInteractionTests: XCTestCase {
    private final class Service: CoolingService {
        var state = CoolingServiceState.enabled
        var value = HardwareStatus()
        var requests: [HardwareRequest] = []
        var holdNext = false
        var gate: CheckedContinuation<Void, Never>?
        init() {
            value.supportsControl = true; value.fanAvailability = .controllable
            value.temperature = 65
            value.fans = [.init(id: 0, rpm: 2400, minimum: 1200, maximum: 6300, manual: false)]
        }
        func register() throws { state = .enabled }
        func unregister() async throws { XCTFail("This test does not uninstall the service") }
        func invalidate() {}
        func localStatus() async -> HardwareStatus { value }
        func request(_ request: HardwareRequest) async throws -> HardwareStatus {
            requests.append(request)
            if request.operation == .configure {
                if holdNext { holdNext = false; await withCheckedContinuation { gate = $0 } }
                let policy = try XCTUnwrap(request.configuration?.fan)
                value.policy = policy; value.active = policy.mode != .automatic
                value.fans = value.fans.map {
                    .init(id: $0.id, rpm: $0.rpm, minimum: $0.minimum, maximum: $0.maximum, manual: value.active)
                }
            }
            return value
        }
    }

    private func button(_ id: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.identifier?.rawValue == id { return button }
        return view.subviews.lazy.compactMap { self.button(id, in: $0) }.first
    }

    private func withCleanState() {
        _ = NSApplication.shared
        let keys = [SettingsKey.panelTabs, "hardwareUpdateTransaction", "hardwareUpdateUnregistered"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        let snapshot = Snapshot.active
        Snapshot.active = true
        addTeardownBlock { @MainActor in
            Snapshot.active = snapshot
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
    }

    func testModeClickAppliesWithoutASubmitAndSelectsOnlyAfterAcknowledgment() async throws {
        withCleanState()
        let service = Service()
        let model = CoolingController(service: service)
        await model.refresh()
        Snapshot.active = false
        let host = NSHostingView(rootView: CoolingView(controller: model, lang: .en).frame(width: 500))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let maximum = try XCTUnwrap(button("hop.cooling.mode.maximum", in: host))
        XCTAssertEqual(maximum.focusRingType, .none)
        XCTAssertNil(button("hop.cooling.apply", in: host))
        XCTAssertNil(button("hop.cooling.service.approve", in: host))
        service.holdNext = true
        maximum.performClick(nil)
        for _ in 0..<100 where service.gate == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNotNil(service.gate)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(maximum.state, .off)
        let gate = service.gate; service.gate = nil; gate?.resume()
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(model.activeFanMode, .maximum)
        XCTAssertEqual(try XCTUnwrap(button("hop.cooling.mode.maximum", in: host)).state, .on)
        let automatic = try XCTUnwrap(button("hop.cooling.mode.automatic", in: host))
        automatic.performClick(nil)
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(model.snapshot.active)
        XCTAssertNil(model.activeFanMode)
        model.close()
    }

    private func slider(in view: NSView) -> NSSlider? {
        if let slider = view as? NSSlider { return slider }
        return view.subviews.lazy.compactMap { self.slider(in: $0) }.first
    }

    func testFixedSliderAppliesTheLastValueAndHasNoTickMarks() async throws {
        withCleanState()
        let service = Service()
        let controller = CoolingController(service: service)
        await controller.refresh()
        Snapshot.active = false
        let host = NSHostingView(rootView: CoolingView(controller: controller, lang: .en).frame(width: 500))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close(); controller.close() }
        host.layoutSubtreeIfNeeded()
        try XCTUnwrap(button("hop.cooling.mode.fixed", in: host)).performClick(nil)
        for _ in 0..<100 where controller.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        host.layoutSubtreeIfNeeded()
        let control = try XCTUnwrap(slider(in: host))
        XCTAssertEqual(control.numberOfTickMarks, 0)
        XCTAssertFalse(control.allowsTickMarkValuesOnly)
        XCTAssertTrue(control.isContinuous)
        XCTAssertEqual(control.focusRingType, .none)
        for value in [3000.0, 3500, 4000] {
            control.doubleValue = value
            control.sendAction(control.action, to: control.target)
        }
        for _ in 0..<100 where controller.busy || controller.pendingFanPolicy != nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(controller.snapshot.policy.targets[0], 4000)
        XCTAssertEqual(controller.activeFanMode, .fixed)
    }

    func testNativeCoolingControlsFitBothThemesAndLongTranslations() async throws {
        withCleanState()
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: Theme.themeKey)
        defer {
            if let saved { defaults.set(saved, forKey: Theme.themeKey) }
            else { defaults.removeObject(forKey: Theme.themeKey) }
        }
        for lang in [AppLanguage.en, .ru, .de, .fr] {
            for dark in [false, true] {
                defaults.set(dark ? "dark" : "light", forKey: Theme.themeKey)
                for mode in FanPolicy.Mode.allCases {
                    Snapshot.active = true
                    let service = Service()
                    service.value.policy = .init(mode: mode, targets: [0: 6617, 1: 6567])
                    service.value.active = mode != .automatic
                    service.value.fans = [
                        .init(id: 0, rpm: 2314, minimum: 2317, maximum: 7826, manual: mode != .automatic),
                        .init(id: 1, rpm: 2505, minimum: 2317, maximum: 7826, manual: mode != .automatic)
                    ]
                    let controller = CoolingController(service: service)
                    await controller.refresh()
                    Snapshot.active = false
                    let content = CoolingView(controller: controller, lang: lang).frame(width: 500)
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(\.colorScheme, dark ? .dark : .light)
                    let host = NSHostingView(rootView: content)
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
                        styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false; window.contentView = host
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    host.layoutSubtreeIfNeeded()
                    let height = ceil(host.fittingSize.height)
                    XCTAssertGreaterThan(height, 200); XCTAssertLessThan(height, 650)
                    window.setContentSize(NSSize(width: 500, height: height)); host.layoutSubtreeIfNeeded()
                    XCTAssertEqual(try XCTUnwrap(button("hop.cooling.mode." + mode.rawValue, in: host)).state, .on)
                    XCTAssertNil(button("hop.cooling.service.approve", in: host))
                    if let directory = ProcessInfo.processInfo.environment["HOP_PLUGIN_RENDER_DIR"] {
                        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                            URL(fileURLWithPath: directory).appendingPathComponent(
                                "cooling-native-\(lang.rawValue)-\(dark ? "dark" : "light")-\(mode.rawValue).png"))
                    }
                    window.close(); controller.close()
                }
            }
        }
    }

    func testApprovalActionIsReachableEvenWhenLocalFanControlCannotBeRead() async throws {
        withCleanState()
        let service = Service()
        service.state = .approval; service.value.fans = []
        service.value.supportsControl = false; service.value.fanAvailability = .unavailable
        var opened = 0
        let controller = CoolingController(service: service, openSettings: { opened += 1 })
        await controller.refresh()
        Snapshot.active = false
        let host = NSHostingView(rootView: CoolingView(controller: controller, lang: .en).frame(width: 500))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let approve = try XCTUnwrap(button("hop.cooling.service.approve", in: host))
        approve.performClick(nil)
        XCTAssertEqual(opened, 1)
        XCTAssertTrue(service.requests.isEmpty)
    }
}
