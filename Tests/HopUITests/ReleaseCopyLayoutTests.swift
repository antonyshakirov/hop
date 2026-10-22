import AppKit
import HopCore
import XCTest
@testable import Hop

@MainActor
final class ReleaseCopyLayoutTests: XCTestCase {
    func testUpcomingReleaseCopyRenderedLines() {
        let keys: [L10nKey] = [.news24Mixer, .news24Icon, .news24Torrents, .news24Windows]
        for lang in AppLanguage.allCases {
            let short = L10n.shortWords(lang).union(lang == .en ? ["an", "the", "of", "to", "in", "on", "for", "with", "from", "without", "through", "and", "or"] : [])
            for (size, widths) in [(CGFloat(10), [CGFloat(304)]), (12, [432, 620])] {
                let font = lang.isRTL ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
                                      : NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
                for key in keys {
                    let copy = L10n.t(key, lang)
                    for width in widths {
                        let text = NSTextStorage(string: copy, attributes: [.font: font])
                        let manager = NSLayoutManager()
                        let container = NSTextContainer(containerSize: NSSize(width: width, height: 10000))
                        container.lineFragmentPadding = 0
                        manager.addTextContainer(container); text.addLayoutManager(manager)
                        manager.ensureLayout(for: container)
                        let glyphs = manager.glyphRange(for: container)
                        XCTAssertGreaterThan(glyphs.length, 0)
                        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, range, _ in
                            let characters = manager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
                            let line = (copy as NSString).substring(with: characters).trimmingCharacters(in: .whitespacesAndNewlines)
                            let words = line.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                            let first = words.first?.trimmingCharacters(in: .punctuationCharacters) ?? ""
                            let last = words.last?.trimmingCharacters(in: .punctuationCharacters) ?? ""
                            XCTAssertFalse(short.contains(last), "\(lang.rawValue).\(key) at \(size)/\(width): \(line)")
                            XCTAssertFalse(L10n.trailingWords(lang).contains(first), "\(lang.rawValue).\(key) at \(size)/\(width): \(line)")
                            XCTAssertFalse(line.hasPrefix("—") || line.hasPrefix("–"), "\(lang.rawValue).\(key): \(line)")
                        }
                    }
                }
            }
        }
    }
}
