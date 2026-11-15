import AppKit
import CoreText
import HopCore
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class ClipboardPickerRenderingTests: XCTestCase {
    func testPickerLabelsFitTheirRenderedWidthInEveryLanguage() {
        for lang in AppLanguage.allCases {
            for key in [L10nKey.clipboardNoResults, .clipboardEmpty, .searchLabel] {
                let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
                let line = CTLineCreateWithAttributedString(NSAttributedString(
                    string: L10n.t(key, lang), attributes: [.font: font]))
                XCTAssertLessThan(CTLineGetTypographicBounds(line, nil, nil, nil), 440,
                                  "\(lang.rawValue).\(key.rawValue) must fit the actual picker")
            }
        }
    }

    func testPickerRendersHistorySearchAndEmptyResultsInBothThemes() throws {
        let defaults = UserDefaults.standard
        let savedTheme = defaults.object(forKey: Theme.themeKey)
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer {
            Snapshot.active = wasSnapshot
            if let savedTheme { defaults.set(savedTheme, forKey: Theme.themeKey) }
            else { defaults.removeObject(forKey: Theme.themeKey) }
        }
        let output = ProcessInfo.processInfo.environment["HOP_CLIPBOARD_RENDER_DIR"]
        if let output { try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true) }
        let items = [ClipboardItem(text: "https://hop.tools"),
                     ClipboardItem(text: "meeting notes.md", filePaths: ["/synthetic/meeting notes.md"]),
                     ClipboardItem(text: "a complete long body stays in its own file", textFile: "long.txt", textBytes: 50000),
                     ClipboardItem(text: "#8AB4F8", colorHex: "8AB4F8"),
                     ClipboardItem(text: "a long line of copied text that keeps the content whole and truncates its preview only"),
                     ClipboardItem(text: "draft one"), ClipboardItem(text: "draft two"),
                     ClipboardItem(text: "draft three"), ClipboardItem(text: "draft four")]
        for lang in [AppLanguage.en, .ru, .de, .fr, .ar] {
            for dark in [false, true] {
                defaults.set(dark ? "dark" : "light", forKey: Theme.themeKey)
                for state in ["history", "search", "empty", "no-results"] {
                    let model = ClipboardPickerModel(items: state == "empty" ? [] : items)
                    if state == "search" { model.query = "draft" }
                    if state == "no-results" { model.query = "absent" }
                    let view = ClipboardPickerView(model: model, lang: lang, choose: { _ in }, preview: true)
                        .frame(width: 540, height: 434)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.nsImage)
                    XCTAssertEqual(image.size, NSSize(width: 540, height: 434))
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    if let output {
                        try png.write(to: URL(fileURLWithPath: output)
                            .appendingPathComponent("picker-\(lang.rawValue)-\(dark ? "dark" : "light")-\(state).png"))
                    }
                }
            }
        }
    }
}
