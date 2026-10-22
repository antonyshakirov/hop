import AppKit
import HopCore
import XCTest
@testable import Hop

@MainActor
final class SoundDocumentationLayoutTests: XCTestCase {
    func testMixerHelpRenderedLinesKeepShortWordsAttached() {
        for lang in AppLanguage.allCases {
            let paragraph = L10n.t(.docSoundFull, lang).components(separatedBy: "\n\n").last!
            let font = lang.isRTL ? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
                                  : NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            for width in [CGFloat(432), 472, 620] {
                let text = NSTextStorage(string: paragraph, attributes: [.font: font])
                let manager = NSLayoutManager()
                let container = NSTextContainer(containerSize: NSSize(width: width, height: 10000))
                container.lineFragmentPadding = 0
                manager.addTextContainer(container); text.addLayoutManager(manager)
                manager.ensureLayout(for: container)
                let glyphs = manager.glyphRange(for: container)
                XCTAssertGreaterThan(glyphs.length, 0)
                manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, range, _ in
                    let characters = manager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
                    let line = (paragraph as NSString).substring(with: characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    let words = line.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    let first = words.first?.trimmingCharacters(in: .punctuationCharacters) ?? ""
                    let last = words.last?.trimmingCharacters(in: .punctuationCharacters) ?? ""
                    XCTAssertFalse(L10n.shortWords(lang).contains(last), "\(lang.rawValue) at \(width): \(line)")
                    XCTAssertFalse(L10n.trailingWords(lang).contains(first), "\(lang.rawValue) at \(width): \(line)")
                    XCTAssertFalse(line.hasPrefix("—") || line.hasPrefix("–"), "\(lang.rawValue) at \(width): \(line)")
                }
            }
        }
    }
}
