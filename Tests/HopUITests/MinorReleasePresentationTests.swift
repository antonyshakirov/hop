import AppKit
import CoreText
import HopCore
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class MinorReleasePresentationTests: XCTestCase {
    func testPreparedNotesMatchTheCardInEveryLanguage() throws {
        var prepared: [String: String] = [:]
        for lang in AppLanguage.allCases {
            let prefix = "2.5.0 – 2026-11-12\n\n• " + L10n.t(.news25Bar, lang)
                + "\n\n• " + L10n.t(.news25Groups, lang) + "\n\n"
            prepared[lang.rawValue] = prefix
            XCTAssertTrue(L10n.t(.docNews, lang).hasPrefix(prefix), lang.rawValue)
        }
        if let output = ProcessInfo.processInfo.environment["HOP_RELEASE_COPY_OUTPUT"] {
            try JSONSerialization.data(withJSONObject: prepared, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: output))
        }
    }

    func testGroupTitlesAndCardCopyWrapInEveryLanguage() {
        for lang in AppLanguage.allCases {
            let font: (CGFloat) -> NSFont = { size in
                lang.isRTL ? .monospacedDigitSystemFont(ofSize: size, weight: .medium)
                    : .monospacedSystemFont(ofSize: size, weight: .medium)
            }
            let titles = ModuleCatalog.settingsGroups(in: []).map { SettingsSidebar.groupTitle($0.id, lang: lang) }
            XCTAssertEqual(Set(titles).count, 5, lang.rawValue)
            for title in titles {
                checkLines(title.uppercased(), width: 188, font: font(9), tracking: 0.6, lang: lang)
            }
            for key in [L10nKey.news25Bar, .news25Groups, .news25Action] {
                checkLines(L10n.t(key, lang), width: 304, font: font(10), lang: lang)
            }
            for module in ModuleCatalog.allIDs {
                guard let key = ModulePresentation.titleKey(module) else {
                    XCTFail(module); continue
                }
                XCTAssertEqual(SettingsSelection(id: "module:" + module), .module(module))
                XCTAssertLessThanOrEqual(checkLines(L10n.t(key, lang), width: 160,
                    font: font(11), lang: lang), 2, "\(lang.rawValue) \(module)")
            }
        }
    }

    func testGroupedSidebarRendersWithSelectedModuleInBothThemes() throws {
        let defaults = UserDefaults.standard
        let keys = [Theme.themeKey, SettingsKey.appLanguage, SettingsKey.panelTabs]
        let saved = keys.map { defaults.object(forKey: $0) }
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        defer {
            Snapshot.active = wasSnapshot
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for lang in [AppLanguage.en, .ru, .de, .fr, .ar] {
            defaults.set(lang.rawValue, forKey: SettingsKey.appLanguage)
            for dark in [false, true] {
                defaults.set(dark ? "dark" : "light", forKey: Theme.themeKey)
                let renderer = ImageRenderer(content: SettingsSidebar(lang: lang,
                    selection: .constant("module:system"))
                    .background(Theme.background)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                XCTAssertEqual(image.size.width, SettingsSidebar.width)
                XCTAssertGreaterThan(image.size.height, 900)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 1)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(png.count, 10_000)
                if let directory = ProcessInfo.processInfo.environment["HOP_250_RENDER_DIR"] {
                    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                    try png.write(to: URL(fileURLWithPath: directory)
                        .appendingPathComponent("sidebar-\(lang.rawValue)-\(dark ? "dark" : "light").png"))
                }
            }
        }
    }

    @discardableResult
    private func checkLines(_ text: String, width: Double, font: NSFont, tracking: Double = 0,
                            lang: AppLanguage, file: StaticString = #filePath, line: UInt = #line) -> Int {
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .kern: tracking])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 2000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        let lines = (CTFrameGetLines(frame) as! [CTLine]).map { ctLine -> String in
            let range = CTLineGetStringRange(ctLine)
            return (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        XCTAssertFalse(lines.isEmpty, file: file, line: line)
        let short = L10n.shortWords(lang).union(lang == .en
            ? ["an", "the", "of", "to", "in", "on", "for", "with", "from", "without", "through", "and", "or"]
            : lang == .de ? ["und", "oder", "der", "die", "das", "ein", "eine", "mit", "für", "von", "zu"] : [])
        for rendered in lines.dropLast() {
            let last = rendered.components(separatedBy: .whitespaces).last ?? ""
            XCTAssertFalse(short.contains(last.lowercased()),
                "\(lang.rawValue) \(width): \(rendered)", file: file, line: line)
        }
        for rendered in lines {
            XCTAssertFalse(rendered.hasPrefix("—") || rendered.hasPrefix("–"), file: file, line: line)
        }
        return lines.count
    }
}
