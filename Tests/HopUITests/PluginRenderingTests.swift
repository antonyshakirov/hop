import AppKit
import CoreText
import SwiftUI
import XCTest
import HopCore
import HopPluginAPI
@testable import Hop
@testable import HopPluginRuntime

@MainActor
private final class RenderingPluginTransport: PluginRuntimeTransport {
    var didStop: ((PluginError) -> Void)?
    var service = RuntimeService()
    func send(_ request: PluginRuntimeRequest) async throws -> PluginRuntimeReply {
        if request.operation == "unload" { service.unload(request.session); return PluginRuntimeReply(request) }
        return PluginRuntimeReply(request, result: try service.execute(request))
    }
    func stop() { service = RuntimeService() }
}

@MainActor
final class PluginRenderingTests: XCTestCase {
    func testInstalledSearchMatchesMetadataAndKeepsImportsOff() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PluginStore(directory: directory)
        let root = try XCTUnwrap(Bundle.module.url(forResource: "PluginFixtures", withExtension: nil))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("desk-panel-1.0.0.hopplugin"))) as? [String: Any])
        var manifest = try XCTUnwrap(object["manifest"] as? [String: Any])
        manifest["author"] = "Zoë Example"; object["manifest"] = manifest
        let desk = try store.install(JSONSerialization.data(withJSONObject: object), origin: "local")
        let timer = try store.install(Data(contentsOf: root.appendingPathComponent("auto-break-1.0.0.hopplugin")), origin: "local")
        let records = [desk, timer]
        XCTAssertEqual(PluginInstalledQuery.filter(records, query: "  ").map(\.id), records.map(\.id))
        for query in ["DESK", "desk-panel", "accent", "zoe"] {
            XCTAssertEqual(PluginInstalledQuery.filter(records, query: query).map(\.id), [desk.id])
        }
        XCTAssertEqual(PluginInstalledQuery.filter(records, query: "auto-break").map(\.id), [timer.id])
        XCTAssertTrue(PluginInstalledQuery.filter(records, query: "not installed").isEmpty)
        XCTAssertTrue(store.state.records.allSatisfy { !$0.wantedEnabled && !$0.canRun })
    }
    func testPausedInstalledCardRetryRequestsApprovalAndRemovalStillWorks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PluginStore(directory: directory)
        let root = try XCTUnwrap(Bundle.module.url(forResource: "PluginFixtures", withExtension: nil))
        let installed = try store.install(Data(contentsOf: root.appendingPathComponent("desk-panel-1.0.0.hopplugin")), origin: "local")
        try store.approve(installed.id, digest: installed.digest, capabilities: Set(installed.package.manifest.capabilities))
        try store.quarantine(installed.id, reason: PluginError.runtimeUnavailable.rawValue)
        let paused = try XCTUnwrap(store.record(installed.id))
        XCTAssertTrue(paused.wantedEnabled)
        var requested = 0, disabled = 0, removed = 0
        let host = NSHostingView(rootView: PluginInstalledActions(record: paused, active: false, lang: .en,
            requestEnable: { requested += 1 }, disable: { disabled += 1 }, remove: { removed += 1 }).frame(width: 160, height: 140))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 140), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func buttons(_ view: NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
        try XCTUnwrap(buttons(host).first { $0.identifier?.rawValue == "hop.plugins.retry." + paused.id }).performClick(nil)
        XCTAssertEqual(requested, 1); XCTAssertEqual(disabled, 0)
        XCTAssertFalse(try XCTUnwrap(store.record(paused.id)).canRun)
        try XCTUnwrap(buttons(host).first { $0.identifier?.rawValue == "hop.plugins.remove." + paused.id }).performClick(nil)
        XCTAssertEqual(removed, 1)
    }
    func testNativeInstalledToggleCancelApproveDisableAndRemove() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transport = RenderingPluginTransport()
        let manager = PluginManager(engine: TimerEngine(), directory: directory, transport: transport)
        var windows: [NSWindow] = [], requested: PluginRecord?
        defer { manager.disableAll(); windows.forEach { $0.close() }; try? FileManager.default.removeItem(at: directory) }
        func host(_ view: AnyView) -> NSView {
            let host = NSHostingView(rootView: view.frame(width: 480, height: 240))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; windows.append(window)
            host.layoutSubtreeIfNeeded(); return host
        }
        func controls<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { controls($0, type) }
        }
        func card() throws -> NSView {
            let record = try XCTUnwrap(manager.records.first)
            return host(AnyView(PluginInstalledActions(record: record, active: manager.active.contains(record.id), lang: .en,
                requestEnable: { requested = record }, disable: { manager.disable(record.id) }, remove: { manager.remove(record.id) })))
        }
        func toggle(_ view: NSView, enabled: Bool) throws {
            let control = try XCTUnwrap(controls(view, NSSwitch.self).first)
            control.state = enabled ? .on : .off
            XCTAssertTrue(control.sendAction(control.action, to: control.target))
        }
        func approval() throws -> NSView {
            let record = try XCTUnwrap(requested)
            return host(AnyView(PluginApprovalView(record: record, lang: .en, cancel: { requested = nil }, approve: {
                manager.approve(record.id, digest: record.digest, capabilities: Set(record.package.manifest.capabilities)); requested = nil
            })))
        }
        func click(_ view: NSView, _ id: String) throws {
            try XCTUnwrap(controls(view, NSButton.self).first { $0.identifier?.rawValue == id }).performClick(nil)
        }
        func waitForActive() async throws {
            let deadline = Date().addingTimeInterval(3)
            while manager.active.isEmpty, Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
            XCTAssertFalse(manager.active.isEmpty)
        }
        let root = try XCTUnwrap(Bundle.module.url(forResource: "PluginFixtures", withExtension: nil))
        manager.install(try Data(contentsOf: root.appendingPathComponent("desk-panel-1.0.0.hopplugin")), origin: "local")
        try toggle(card(), enabled: true); XCTAssertNotNil(requested)
        try click(approval(), "hop.plugins.cancel")
        XCTAssertNil(requested); XCTAssertFalse(try XCTUnwrap(manager.records.first).wantedEnabled)
        XCTAssertTrue(transport.service.contexts.isEmpty)
        try toggle(card(), enabled: true); try click(approval(), "hop.plugins.approve"); try await waitForActive()
        try toggle(card(), enabled: false); XCTAssertTrue(manager.active.isEmpty); XCTAssertNil(Theme.pluginOverlay)
        try toggle(card(), enabled: true); try click(approval(), "hop.plugins.approve"); try await waitForActive()
        let id = try XCTUnwrap(manager.records.first).id
        try click(card(), "hop.plugins.remove." + id)
        XCTAssertTrue(manager.records.isEmpty); XCTAssertTrue(manager.active.isEmpty); XCTAssertNil(Theme.pluginOverlay)
        XCTAssertTrue(try PluginStore(directory: directory).state.records.isEmpty)
    }
    func testNativeLibraryLinksOpenOnlyTheirPublicDestination() throws {
        var opened: [URL] = []
        let root = PluginLibraryLinks(lang: .en)
            .environment(\.openURL, OpenURLAction { url in opened.append(url); return .handled })
            .padding(20).frame(width: 650)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func buttons(_ view: NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
        for (id, expected) in [("hop.plugins.contribute", PluginLibraryResources.contribute)] {
            let link = try XCTUnwrap(buttons(host).first { $0.identifier?.rawValue == id })
            link.performClick(nil)
            XCTAssertEqual(opened.last, expected)
        }
        XCTAssertEqual(opened.count, 1)
        XCTAssertNil(buttons(host).first { $0.identifier?.rawValue == "hop.plugins.repository" })
    }
    func testNativePluginButtonReallyInvokesItsAction() throws {
        let nodes = try JSONDecoder().decode([PluginNode].self, from: Data(#"[{"type":"button","title":"Run","action":"run"}]"#.utf8))
        var performed: [String] = []
        let host = NSHostingView(rootView: PluginNodeView(nodes: nodes, action: { performed.append($0) }, module: { _ in AnyView(EmptyView()) }).frame(width: 300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func buttons(_ view: NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
        let button = try XCTUnwrap(buttons(host).first(where: { $0.title == "Run" }))
        button.performClick(nil)
        XCTAssertEqual(performed, ["run"])
    }
    func testNativeStringSettingWaitsForCommitInsteadOfSendingPartialHex() throws {
        var committed: [String] = []
        let host = NSHostingView(rootView: PluginStringSetting(value: "#5279DB", label: "Accent") { committed.append($0) }.frame(width: 220))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func fields(_ view: NSView) -> [SteadyTextField] { (view as? SteadyTextField).map { [$0] } ?? view.subviews.flatMap(fields) }
        let field = try XCTUnwrap(fields(host).first)
        let coordinator = try XCTUnwrap(field.delegate as? SteadyField.Coordinator)
        field.stringValue = "#44"
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertTrue(committed.isEmpty)
        field.stringValue = "#4466cc"
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertTrue(coordinator.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(committed, ["#4466cc"])
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        XCTAssertEqual(committed, ["#4466cc"])
    }
    func testPluginCopyIsCompleteAndWrapsInEveryLanguage() {
        for lang in AppLanguage.allCases {
            let font = lang.isRTL ? NSFont.systemFont(ofSize: 11) : NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
            for key in PluginText.allCases {
                let text = PluginCopy.text(key, lang)
                XCTAssertFalse(text.isEmpty)
                for width in [220.0, 400.0] {
                    let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
                    let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 2000), transform: nil), nil)
                    let lines = CTFrameGetLines(frame) as! [CTLine]
                    XCTAssertFalse(lines.isEmpty)
                    for line in lines.dropLast() {
                        let range = CTLineGetStringRange(line)
                        let rendered = (text as NSString).substring(with: NSRange(location: range.location, length: range.length)).trimmingCharacters(in: .whitespacesAndNewlines)
                        let last = rendered.components(separatedBy: .whitespaces).last ?? ""
                        XCTAssertFalse(L10n.shortWords(lang).contains(last.lowercased()), "\(lang.rawValue) \(key): \(rendered)")
                    }
                }
            }
        }
    }
    func testNativeSettingsAndRealExampleOverlayRenderBothThemesWithoutChangingBasePrefs() async throws {
        let defaults = UserDefaults.standard
        let keys = [Theme.themeKey, SettingsKey.panelTabs, SettingsKey.appLanguage]
        let saved = keys.map { defaults.object(forKey: $0) }
        let snapshot = Snapshot.active
        Snapshot.active = true
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            Snapshot.active = snapshot; Theme.pluginOverlay = nil
            for (key, value) in zip(keys, saved) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
            try? FileManager.default.removeItem(at: directory)
        }
        let model = AppModel(preview: true)
        defer { model.soundCallMix.shutdown() }
        let manager = PluginManager(engine: model.engine, directory: directory, transport: RenderingPluginTransport())
        model.plugins = manager
        let root = try XCTUnwrap(Bundle.module.url(forResource: "PluginFixtures", withExtension: nil))
        for dark in [false, true] {
            defaults.set(dark ? "dark" : "light", forKey: Theme.themeKey)
            for lang in AppLanguage.allCases {
                defaults.set(lang.rawValue, forKey: SettingsKey.appLanguage)
                try render(AnyView(PluginSettingsView(manager: manager, lang: lang).padding(20).frame(width: 650).background(Theme.background)
                    .environment(\.colorScheme, dark ? .dark : .light).environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)),
                    name: "plugins-empty-\(lang.rawValue)-\(dark ? "dark" : "light")", maximumHeight: 240)
            }
        }
        for name in ["desk-panel", "auto-break"] {
            manager.install(try Data(contentsOf: root.appendingPathComponent(name + "-1.0.0.hopplugin")), origin: "local")
        }
        defaults.set("en", forKey: SettingsKey.appLanguage)
        _ = PanelView(initial: .firstSpace)
        let baseline = keys.map { defaults.object(forKey: $0) as? String }
        let desk = try XCTUnwrap(manager.records.first(where: { $0.id == "desk-panel" }))
        manager.approve(desk.id, digest: desk.digest, capabilities: Set(desk.package.manifest.capabilities))
        let deadline = Date().addingTimeInterval(3)
        while manager.panel == nil, Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(manager.panel?.panel.width, 420)
        for dark in [false, true] {
            defaults.set(dark ? "dark" : "light", forKey: Theme.themeKey)
            for lang in [AppLanguage.en, .ru, .de, .fr, .ar] {
                defaults.set(lang.rawValue, forKey: SettingsKey.appLanguage)
                try render(AnyView(PluginSettingsView(manager: manager, lang: lang).padding(20).frame(width: 650).background(Theme.background)
                    .environment(\.colorScheme, dark ? .dark : .light).environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)),
                    name: "plugins-settings-\(lang.rawValue)-\(dark ? "dark" : "light")", maximumHeight: 1000)
            }
            try render(AnyView(PanelView(initial: .firstSpace).environmentObject(model).environment(\.colorScheme, dark ? .dark : .light)),
                       name: "plugins-desk-panel-\(dark ? "dark" : "light")", maximumHeight: 1400)
        }
        let chosenLanguage = defaults.string(forKey: SettingsKey.appLanguage)
        manager.disable(desk.id)
        XCTAssertNil(Theme.pluginOverlay)
        XCTAssertNil(manager.panel)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.panelTabs), baseline[1])
        XCTAssertEqual(defaults.string(forKey: SettingsKey.appLanguage), chosenLanguage)
        defaults.set("en", forKey: SettingsKey.appLanguage)
        for dark in [false, true] {
            defaults.set(dark ? "dark" : "light", forKey: Theme.themeKey)
            Snapshot.active = false
            model.settingsSectionRequest = "plugins"
            let view = PanelView(standaloneSettings: true).environmentObject(model)
                .frame(width: 940, height: 720).environment(\.colorScheme, dark ? .dark : .light)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 720), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            host.layoutSubtreeIfNeeded()
            let deadline = Date().addingTimeInterval(2)
            while model.settingsSectionRequest != nil, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertNil(model.settingsSectionRequest)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            if let path = ProcessInfo.processInfo.environment["HOP_PLUGIN_RENDER_DIR"] {
                try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("plugins-full-window-\(dark ? "dark" : "light").png"))
            }
            window.close()
            Snapshot.active = true
        }
    }
    private func render(_ view: AnyView, name: String, maximumHeight: Double) throws {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        XCTAssertGreaterThan(size.width, 0); XCTAssertGreaterThan(size.height, 0); XCTAssertLessThanOrEqual(size.height, maximumHeight)
        host.setFrameSize(size); window.setContentSize(size); host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        if let path = ProcessInfo.processInfo.environment["HOP_PLUGIN_RENDER_DIR"] {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }
}
