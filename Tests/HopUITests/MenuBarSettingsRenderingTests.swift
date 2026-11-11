import AppKit
import CoreText
import HopCore
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class MenuBarSettingsRenderingTests: XCTestCase {
    func testChangedSettingsTextWrapsInEveryLanguageAtMinimumAndRegularWidths() {
        let keys: [L10nKey] = [.barTitle, .barRotating, .barTogether, .barDetailed, .barDiskFree,
            .barSwap, .barCycles, .barAdapter, .menuBarIconOnly]
        for lang in AppLanguage.allCases {
            let font = lang.isRTL ? NSFont.systemFont(ofSize: 12, weight: .medium)
                : NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            for width in [240.0, 340.0, 440.0] {
                let texts = keys.map { L10n.t($0, lang) }
                    + MenuBarMetric.allCases.map { MenuBarReading.title($0, lang: lang) }
                for text in texts { checkLines(text, width: width, font: font, lang: lang) }
            }
            var sample = StatsSample()
            sample.memUsed = 19.9 * 1_073_741_824
            sample.memTotal = 24 * 1_073_741_824
            let tooltip = MenuBarReading.sensor(.memory, sample: sample, detailed: false,
                lang: lang, temperatureUnit: "c").tooltip(lang: lang)
            for width in [240.0, 400.0] {
                checkLines(tooltip, width: width, font: NSFont.toolTipsFont(ofSize: 0), lang: lang)
            }
            let hintFont = lang.isRTL ? NSFont.systemFont(ofSize: 10, weight: .medium)
                : NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
            for width in [500.0, 600.0] {
                checkLines(L10n.t(.barHint, lang), width: width, font: hintFont, lang: lang)
            }
            let captionFont = lang.isRTL ? NSFont.systemFont(ofSize: 9, weight: .medium)
                : NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
            for width in [240.0, 340.0] {
                checkLines(MenuBarReading.mixerLegend(lang: lang), width: width, font: captionFont, lang: lang)
            }
        }
    }

    func testSettingsRenderInBothThemesWithSelectedAndIconOnlyStates() throws {
        let defaults = UserDefaults.standard
        let keys = [Theme.themeKey, SettingsKey.appLanguage, SettingsKey.menuBarReadings,
                    SettingsKey.menuBarIconOnly, SettingsKey.showMenuBarCountdown, SettingsKey.panelTabs]
        let saved = keys.map { defaults.object(forKey: $0) }
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer {
            Snapshot.active = wasSnapshot
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        defaults.set(false, forKey: SettingsKey.showMenuBarCountdown)
        var config = MenuBarReadings()
        config.enabled = [.disk, .memory, .cpu, .battery]
        config.order.removeAll { $0 == .disk || $0 == .memory }
        config.order.insert(contentsOf: [.disk, .memory], at: 0)
        config.layout = .together
        defaults.set(config.encoded, forKey: SettingsKey.menuBarReadings)
        let model = AppModel(preview: true)
        defer { model.soundCallMix.shutdown() }
        let output = ProcessInfo.processInfo.environment["HOP_MENU_BAR_RENDER_DIR"]
        if let output { try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true) }
        for lang in [AppLanguage.en, .ru, .de, .fr, .ar] {
            defaults.set(lang.rawValue, forKey: SettingsKey.appLanguage)
            for dark in [false, true] {
                defaults.set(dark ? "dark" : "light", forKey: Theme.themeKey)
                for width in [548.0, 648.0] {
                    defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
                    let view = MenuBarSettingsView(lang: lang).environmentObject(model)
                        .padding(14).frame(width: width).background(Theme.background)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.nsImage)
                    XCTAssertEqual(image.size.width, width)
                    XCTAssertGreaterThan(image.size.height, 700)
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    if let output {
                        let name = "menu-bar-\(lang.rawValue)-\(dark ? "dark" : "light")-\(Int(width)).png"
                        try png.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
                    }
                }
            }
        }
        defaults.set(true, forKey: SettingsKey.menuBarIconOnly)
        let renderer = ImageRenderer(content: MenuBarSettingsView(lang: .en)
            .environmentObject(model).padding(14).frame(width: 548).background(Theme.background))
        XCTAssertNotNil(renderer.nsImage)
    }

    private func checkLines(_ text: String, width: Double, font: NSFont, lang: AppLanguage,
                            file: StaticString = #filePath, line: UInt = #line) {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 2000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        let lines = (CTFrameGetLines(frame) as! [CTLine]).map { ctLine -> String in
            let range = CTLineGetStringRange(ctLine)
            return (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        XCTAssertFalse(lines.isEmpty, file: file, line: line)
        for rendered in lines.dropLast() {
            let last = rendered.components(separatedBy: .whitespaces).last ?? ""
            XCTAssertFalse(L10n.shortWords(lang).contains(last.lowercased()),
                "\(lang.rawValue) \(width): \(rendered)", file: file, line: line)
        }
        for rendered in lines {
            XCTAssertFalse(rendered.hasPrefix("—") || rendered.hasPrefix("–"),
                "\(lang.rawValue) \(width): \(rendered)", file: file, line: line)
        }
    }
}
