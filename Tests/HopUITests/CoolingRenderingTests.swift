import AppKit
import CoreText
import HopCore
import HopHardwareKit
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class CoolingRenderingTests: XCTestCase {
    func testReportedFanReadingsRemainVisibleWhenControlSchemaIsUnknown() async throws {
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = wasSnapshot }
        let service = RenderCoolingService("unsupported")
        let controller = CoolingController(service: service)
        await controller.refresh()
        let empty = try XCTUnwrap(ImageRenderer(content: CoolingView(controller: controller, lang: .en).frame(width: 500)).nsImage)
        service.status.fans = [.init(id: 0, rpm: 2400, minimum: 1200, maximum: 6300, manual: false)]
        service.status.supportsControl = false
        await controller.refresh()
        let image = try XCTUnwrap(ImageRenderer(content: CoolingView(controller: controller, lang: .en).frame(width: 500)).nsImage)
        XCTAssertGreaterThan(image.size.height, empty.size.height + 55)
        XCTAssertLessThan(image.size.height, 500)
        if let directory = ProcessInfo.processInfo.environment["HOP_PLUGIN_RENDER_DIR"] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("cooling-readings-without-controls.png"))
        }
    }

    func testMonitorCoolingVisibilityPreferenceRemovesAndRestoresTheRow() throws {
        let defaults = UserDefaults.standard
        let key = "monitorCoolingVisible"
        let saved = defaults.object(forKey: key), wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer {
            Snapshot.active = wasSnapshot
            if let saved { defaults.set(saved, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        let stats = SystemStatsController()
        func height() throws -> CGFloat {
            try XCTUnwrap(ImageRenderer(content: StatsView(stats: stats, cooling: CoolingController(preview: true), lang: .en, openCooling: {})
                .frame(width: 340).padding(14).background(Theme.background)).nsImage).size.height
        }
        defaults.removeObject(forKey: key)
        let initial = try height()
        defaults.set(false, forKey: key)
        let hidden = try height()
        XCTAssertGreaterThan(initial - hidden, 20)
        defaults.set(true, forKey: key)
        XCTAssertEqual(try height(), initial)
    }

    func testMonitorModeUsesOnlyConfirmedActiveManualPolicy() async {
        let wasSnapshot = Snapshot.active
        let defaults = UserDefaults.standard
        let savedTheme = defaults.object(forKey: Theme.themeKey)
        Snapshot.active = true
        defer {
            Snapshot.active = wasSnapshot
            if let savedTheme { defaults.set(savedTheme, forKey: Theme.themeKey) }
            else { defaults.removeObject(forKey: Theme.themeKey) }
        }
        let stats = SystemStatsController(demo: true)
        let service = RenderCoolingService("enabled")
        let controller = CoolingController(service: service)
        XCTAssertNil(controller.activeFanMode)
        for mode in FanPolicy.Mode.allCases {
            service.status.policy.mode = mode
            service.status.active = false
            await controller.refresh()
            XCTAssertNil(controller.activeFanMode)
            service.status.active = true
            service.status.fans = service.status.fans.map {
                .init(id: $0.id, rpm: $0.rpm, minimum: $0.minimum, maximum: $0.maximum, manual: mode != .automatic)
            }
            await controller.refresh()
            XCTAssertEqual(controller.activeFanMode, mode == .automatic ? nil : mode)
            for lang in [AppLanguage.en, .ru, .de, .fr] {
                for dark in [false, true] {
                    defaults.set(dark ? "dark" : "light", forKey: Theme.themeKey)
                    let view = StatsView(stats: stats, cooling: controller, lang: lang, openCooling: {})
                        .frame(width: 340).padding(14).background(Theme.background)
                        .environment(\.colorScheme, dark ? .dark : .light)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try? XCTUnwrap(renderer.nsImage)
                    XCTAssertNotNil(image)
                    if let image, let directory = ProcessInfo.processInfo.environment["HOP_CLIPBOARD_RENDER_DIR"] {
                        do {
                            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                                .write(to: URL(fileURLWithPath: directory)
                                    .appendingPathComponent("monitor-\(lang.rawValue)-\(dark ? "dark" : "light")-\(mode.rawValue).png"))
                        } catch { XCTFail("Monitor render failed: \(error)") }
                    }
                }
            }
            service.status.restorationPending = true
            await controller.refresh()
            XCTAssertNil(controller.activeFanMode)
            service.status.restorationPending = false
        }
        service.status.active = false
        await controller.refresh()
        XCTAssertNil(controller.activeFanMode)
        service.status.active = true; service.status.policy.mode = .maximum
        service.status.fans = [.init(id: 0, rpm: 6300, minimum: 1200, maximum: 6300, manual: true)]
        await controller.refresh()
        XCTAssertEqual(controller.activeFanMode, .maximum)
        service.state = .approval
        await controller.refresh()
        XCTAssertNil(controller.activeFanMode)
    }

    func testCoolingCopyAndClipboardHelpUseTheExistingTypographyRules() throws {
        var fixed: [String: [String: String]] = [:]
        let keys = L10nKey.allCases.filter { $0.rawValue.hasPrefix("hardware")
            || $0.rawValue.hasPrefix("cooling") || $0 == .docClipboardFull || $0 == .docAwakeFull || $0 == .clipboardNoResults }
        for lang in AppLanguage.allCases {
            var values: [String: String] = [:]
            for key in keys {
                let text = L10n.t(key, lang)
                let glued = HangingWords.glued(text, shortWords: L10n.shortWords(lang), trailing: L10n.trailingWords(lang))
                values[key.rawValue] = glued
                XCTAssertEqual(text, glued, "\(lang.rawValue).\(key.rawValue)")
            }
            fixed[lang.rawValue] = values
        }
        if let directory = ProcessInfo.processInfo.environment["HOP_CLIPBOARD_RENDER_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(fixed).write(to: URL(fileURLWithPath: directory).appendingPathComponent("copy-glued.json"))
        }
    }

    func testHardwarePermissionBannerRendersAtPanelWidth() throws {
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = wasSnapshot }
        let defaults = UserDefaults.standard
        let savedTheme = defaults.object(forKey: Theme.themeKey)
        defer {
            if let savedTheme { defaults.set(savedTheme, forKey: Theme.themeKey) }
            else { defaults.removeObject(forKey: Theme.themeKey) }
        }
        for lang in [AppLanguage.en, .ru, .de, .fr, .ar] {
            for dark in [false, true] {
                defaults.set(dark ? "dark" : "light", forKey: Theme.themeKey)
                for (name, issue) in [("missing", HardwarePermissionIssue.missing), ("approval", .approval),
                                      ("unavailable", .unavailable), ("connection", .connection)] {
                    let view = HardwarePermissionBanner(issue: issue, lang: lang, action: {})
                        .frame(width: 340).padding(14).background(Theme.background)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.nsImage)
                    XCTAssertEqual(image.size.width, 368)
                    XCTAssertLessThan(image.size.height, 200)
                    if let directory = ProcessInfo.processInfo.environment["HOP_CLIPBOARD_RENDER_DIR"] {
                        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                            .write(to: URL(fileURLWithPath: directory)
                                .appendingPathComponent("permission-\(lang.rawValue)-\(dark ? "dark" : "light")-\(name).png"))
                    }
                }
            }
        }
    }

    func testFanlessCoolingContentAndNativeWindowStayCompact() async throws {
        _ = NSApplication.shared
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = wasSnapshot }
        let controller = CoolingController(service: RenderCoolingService("unsupported"))
        await controller.refresh()
        let view = CoolingView(controller: controller, lang: .en).frame(width: 500)
        let image = try XCTUnwrap(ImageRenderer(content: view).nsImage)
        XCTAssertLessThan(image.size.height, 190, "Unsupported hardware must not retain the mode grid or Apply row")
        let window = CoolingWindow(controller: controller)
        defer { window.close() }
        XCTAssertLessThan(window.contentRect(forFrameRect: window.frame).height, 190,
                          "The actual window must shrink with its short content")
    }

    func testNativeWindowRefitsForModeChangesAndKeepsItsLastMeasuredDraftHeight() throws {
        _ = NSApplication.shared
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = wasSnapshot }
        let controller = CoolingController(preview: true)
        let curve = CoolingView(controller: controller, lang: .en, initialPolicy: .init(mode: .curve))
            .frame(width: 500)
        let actualHeight = try XCTUnwrap(ImageRenderer(content: curve).nsImage).size.height
        let window = CoolingWindow(controller: controller)
        defer { window.close() }
        window.fit(contentHeight: actualHeight)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, ceil(actualHeight), accuracy: 1)
        window.fitToContent()
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, ceil(actualHeight), accuracy: 1,
                       "Reopening must use the measured draft, including unapplied curve fields")
        window.fit(contentHeight: 10000)
        let limit = floor(((window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900) * 0.8)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, limit, accuracy: 1)
    }

    func testHostedContentResizeReachesTheWindowThroughItsGeometryCallback() async throws {
        _ = NSApplication.shared
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        let service = RenderCoolingService("unsupported")
        let controller = CoolingController(service: service)
        await controller.refresh()
        Snapshot.active = false
        defer { Snapshot.active = wasSnapshot }
        let window = CoolingWindow(controller: controller)
        defer { window.close() }
        let shortHeight = window.contentRect(forFrameRect: window.frame).height
        service.status.supportsControl = true
        service.status.fanAvailability = .controllable
        service.status.fans = [.init(id: 0, rpm: 1400, minimum: 1000, maximum: 6000, manual: false)]
        await controller.refresh()
        for _ in 0..<20 {
            window.contentView?.layoutSubtreeIfNeeded()
            if window.contentRect(forFrameRect: window.frame).height > shortHeight + 100 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertGreaterThan(window.contentRect(forFrameRect: window.frame).height, shortHeight + 100,
                             "Changing hosted content must reach the real window without calling fit in the test")
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(window.delegate === window)
        window.fit(contentHeight: 10000)
        window.setContentSize(NSSize(width: 500, height: 4000))
        window.windowDidChangeScreen(Notification(name: NSWindow.didChangeScreenNotification, object: window))
        let limit = floor(((window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900) * 0.8)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, limit, accuracy: 1)
    }

    func testCoolingRendersModesAndApprovalInBothThemes() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: Theme.themeKey)
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer {
            Snapshot.active = wasSnapshot
            if let saved { defaults.set(saved, forKey: Theme.themeKey) }
            else { defaults.removeObject(forKey: Theme.themeKey) }
        }
        let directory = ProcessInfo.processInfo.environment["HOP_CLIPBOARD_RENDER_DIR"]
        if let directory { try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true) }
        for lang in [AppLanguage.en, .ru, .de, .fr, .ar] {
            for dark in [false, true] {
                defaults.set(dark ? "dark" : "light", forKey: Theme.themeKey)
                for mode in FanPolicy.Mode.allCases {
                    let view = CoolingView(controller: CoolingController(preview: true), lang: lang,
                        initialPolicy: FanPolicy(mode: mode, targets: [0: 3000, 1: 3200]))
                        .frame(width: 500)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.nsImage)
                    XCTAssertEqual(image.size.width, 500)
                    XCTAssertLessThan(image.size.height, 650)
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                    if let directory {
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                            .write(to: URL(fileURLWithPath: directory)
                                .appendingPathComponent("cooling-\(lang.rawValue)-\(dark ? "dark" : "light")-\(mode.rawValue).png"))
                    }
                }
            }
        }
    }

    func testServiceApprovalAndRestorationStatesRenderWithoutHardwareAccess() async throws {
        let defaults = UserDefaults.standard
        let savedTheme = defaults.object(forKey: Theme.themeKey)
        let transaction = defaults.object(forKey: "hardwareUpdateTransaction")
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defaults.removeObject(forKey: "hardwareUpdateTransaction")
        defer {
            Snapshot.active = wasSnapshot
            if let savedTheme { defaults.set(savedTheme, forKey: Theme.themeKey) }
            else { defaults.removeObject(forKey: Theme.themeKey) }
            if let transaction { defaults.set(transaction, forKey: "hardwareUpdateTransaction") }
        }
        for lang in [AppLanguage.en, .ru, .de, .fr] {
            for dark in [false, true] {
                defaults.set(dark ? "dark" : "light", forKey: Theme.themeKey)
                for name in ["missing", "approval", "pending", "busy", "unsupported"] {
                    let service = RenderCoolingService(name)
                    let controller = CoolingController(service: service)
                    await controller.refresh()
                    XCTAssertEqual(controller.approvalRequired, name == "approval")
                    XCTAssertEqual(controller.snapshot.restorationPending, name == "pending")
                    let view = CoolingView(controller: controller, lang: lang).frame(width: 500)
                        .environment(\.colorScheme, dark ? .dark : .light)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.nsImage)
                    XCTAssertLessThan(image.size.height, 650)
                    if let directory = ProcessInfo.processInfo.environment["HOP_CLIPBOARD_RENDER_DIR"] {
                        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                            .write(to: URL(fileURLWithPath: directory)
                                .appendingPathComponent("cooling-\(lang.rawValue)-\(dark ? "dark" : "light")-\(name).png"))
                    }
                    controller.close()
                }
            }
        }
    }
}

@MainActor
private final class RenderCoolingService: CoolingService {
    var state: CoolingServiceState
    var status: HardwareStatus
    init(_ name: String) {
        state = name == "missing" ? .missing : name == "approval" ? .approval : .enabled
        var value = HardwareStatus()
        if ["enabled", "pending", "busy"].contains(name) {
            value.supportsControl = true; value.fanAvailability = .controllable
            value.fans = [.init(id: 0, rpm: 2314, minimum: 2317, maximum: 7826, manual: false),
                .init(id: 1, rpm: 2505, minimum: 2317, maximum: 7826, manual: false)]
        } else { value.fanAvailability = name == "unsupported" ? .fanless : .unavailable }
        if name == "pending" { value.restorationPending = true; value.reason = .restoreFailed }
        if name == "busy" { value.reason = .busy }
        status = value
    }
    func register() throws { XCTFail("Rendering must not install a service") }
    func unregister() async throws { XCTFail("Rendering must not remove a service") }
    func request(_ request: HardwareRequest) async throws -> HardwareStatus {
        XCTAssertEqual(request.operation, .status)
        return status
    }
    func localStatus() async -> HardwareStatus { status }
    func invalidate() {}
}
