import AppKit
import HopCore
import XCTest
@testable import Hop

@MainActor
final class SoundDocumentationLayoutTests: XCTestCase {
    func testMixerHelpRenderedLinesKeepShortWordsAttached() {
        for lang in AppLanguage.allCases {
            let cases: [(L10nKey, CGFloat, [CGFloat])] = [
                (.docSoundFull, 12, [432, 472, 620]),
                (.soundMixerBackground, 10, [240, 280, 360]),
                (.soundMixerPermission, 10, [432, 440, 480]),
                (.soundMicrophone, 20, [300, 440]),
                (.soundCallMix, 12, [200, 240]),
                (.soundCallStart, 11, [180, 220]),
                (.soundCallStop, 11, [180, 220]),
                (.soundCallHint, 10, [432, 480, 620]),
                (.soundCallCloseHint, 10, [432, 480, 620]),
                (.soundCallFailed, 10, [432, 480, 620]),
                (.soundAppPlaying, 11, [280, 432, 680]),
                (.soundAppIdle, 11, [280, 432, 680]),
                (.soundAppNotRunning, 11, [280, 432, 680]),
                (.soundAppWaiting, 10, [268, 432, 680]),
                (.soundAppRouteFailed, 11, [280, 432, 680]),
                (.soundAppPin, 11, [240, 280, 432]),
                (.soundAppUnpin, 11, [240, 280, 432]),
                (.soundAppMoveUp, 11, [240, 280, 432]),
                (.soundAppMoveDown, 11, [240, 280, 432]),
            ]
            for (key, size, widths) in cases {
            let paragraph = L10n.t(key, lang).components(separatedBy: "\n\n").last!
            let font = lang.isRTL ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
                                  : NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
            for width in widths {
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
}
