import AppKit
import XCTest
@testable import Hop

@MainActor
final class AppIconTests: XCTestCase {
    func testApplyUpdatesTheRunningApplicationIconForBothStyles() throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let previousStyle = defaults.object(forKey: AppIcon.styleKey)
        let previousIcon = NSApp.applicationIconImage
        defer {
            if let previousStyle { defaults.set(previousStyle, forKey: AppIcon.styleKey) }
            else { defaults.removeObject(forKey: AppIcon.styleKey) }
            NSApp.applicationIconImage = previousIcon
        }
        var images: [Data] = []
        for style in ["light", "dark"] {
            let placeholder = NSImage(size: NSSize(width: 8, height: 8))
            NSApp.applicationIconImage = placeholder
            defaults.set(style, forKey: AppIcon.styleKey)
            AppIcon.apply()
            let image = try XCTUnwrap(NSApp.applicationIconImage)
            XCTAssertFalse(image === placeholder)
            XCTAssertEqual(image.size, NSSize(width: 512, height: 512))
            images.append(try XCTUnwrap(image.tiffRepresentation))
        }
        XCTAssertNotEqual(images[0], images[1])
    }

    func testDockIconLabelRenderedLinesInEveryLanguage() {
        for lang in AppLanguage.allCases {
            let copy = L10n.t(.appIconLabel, lang)
            let font = lang.isRTL ? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                                  : NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            for width: CGFloat in [148, 196, 244] {
                let text = NSTextStorage(string: copy, attributes: [.font: font])
                let layout = NSLayoutManager(), container = NSTextContainer(size: NSSize(width: width, height: 1000))
                container.lineFragmentPadding = 0
                layout.addTextContainer(container); text.addLayoutManager(layout)
                layout.ensureLayout(for: container)
                var lines = 0
                layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, used, _, range, _ in
                    lines += 1
                    let line = (copy as NSString).substring(with: layout.characterRange(forGlyphRange: range, actualGlyphRange: nil)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let words = line.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    XCTAssertFalse(L10n.shortWords(lang).contains(words.last ?? ""), "\(lang.rawValue): \(line)")
                    XCTAssertFalse(L10n.trailingWords(lang).contains(words.first ?? ""), "\(lang.rawValue): \(line)")
                    XCTAssertLessThanOrEqual(used.width, width + 1)
                }
                XCTAssertGreaterThan(lines, 0)
                XCTAssertLessThanOrEqual(lines, 2, "\(lang.rawValue), \(width)")
            }
        }
    }

}
