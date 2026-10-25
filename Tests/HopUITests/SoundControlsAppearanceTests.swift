import AppKit
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class SoundControlsAppearanceTests: XCTestCase {
    func testMutedAndDisabledThumbsCoverTheTrackInBothThemes() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: Theme.themeKey)
        defer {
            if let previous { defaults.set(previous, forKey: Theme.themeKey) }
            else { defaults.removeObject(forKey: Theme.themeKey) }
        }
        for theme in ["dark", "light"] {
            defaults.set(theme, forKey: Theme.themeKey)
            for (subdued, enabled) in [(true, true), (false, false)] {
                func center(on background: Color) throws -> NSColor {
                    let slider = MiniSlider(value: .constant(50), range: 0...100, width: 200,
                        showsNumber: false, subdued: subdued)
                        .disabled(!enabled).frame(width: 200, height: 20).background(background)
                    let renderer = ImageRenderer(content: slider)
                    renderer.scale = 1
                    let image = try XCTUnwrap(renderer.nsImage)
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                    return try XCTUnwrap(bitmap.colorAt(x: 100, y: 10)?.usingColorSpace(.sRGB))
                }
                let red = try center(on: .red), blue = try center(on: .blue)
                XCTAssertEqual(red.redComponent, blue.redComponent, accuracy: 0.02)
                XCTAssertEqual(red.greenComponent, blue.greenComponent, accuracy: 0.02)
                XCTAssertEqual(red.blueComponent, blue.blueComponent, accuracy: 0.02)
            }
        }
    }

    func testPresetActionRenderedLinesInEveryLanguage() {
        for lang in AppLanguage.allCases {
            for key in [L10nKey.soundAddApplication, .soundResetApplications] {
                let copy = L10n.t(key, lang)
                let font = lang.isRTL ? NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
                                      : NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
                for width: CGFloat in [160, 240, 320] {
                    let text = NSTextStorage(string: copy, attributes: [.font: font])
                    let layout = NSLayoutManager(), container = NSTextContainer(size: NSSize(width: width, height: 1000))
                    container.lineFragmentPadding = 0; layout.addTextContainer(container); text.addLayoutManager(layout)
                    layout.ensureLayout(for: container)
                    layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, range, _ in
                        let line = (copy as NSString).substring(with: layout.characterRange(forGlyphRange: range, actualGlyphRange: nil)).trimmingCharacters(in: .whitespacesAndNewlines)
                        let words = line.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                        XCTAssertFalse(L10n.shortWords(lang).contains(words.last ?? ""), "\(lang.rawValue): \(line)")
                        XCTAssertFalse(L10n.trailingWords(lang).contains(words.first ?? ""), "\(lang.rawValue): \(line)")
                    }
                }
            }
        }
    }
}
