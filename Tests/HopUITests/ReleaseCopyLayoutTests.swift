import AppKit
import HopCore
import XCTest
@testable import Hop

@MainActor
final class ReleaseCopyLayoutTests: XCTestCase {
    func testUpcomingReleaseCopyRenderedLines() {
        let keys: [L10nKey] = [.news25Cooling, .news25Lid, .news25Clipboard,
            .news24Mixer, .news24AI, .news24Icon, .news24Torrents, .news24Windows, .onbSoundTitle, .onbSoundBody]
        verifyRenderedLines(keys, dimensions: [(10, [304]), (12, [432, 620])])
    }

    func testHardwarePermissionBannerRenderedLines() {
        verifyRenderedLines([.hardwareInstallHint, .hardwareApprovalHint, .hardwareConnection,
            .hardwareSignedRequired, .hardwareInstall, .hardwareApprove, .coolingTitle],
            dimensions: [(10, [298, 316])])
    }

    func testMonitorCoolingModeLabelsFitTheTrailingSlot() {
        for lang in AppLanguage.allCases {
            for key in [L10nKey.coolingMaximum, .coolingFixed, .coolingCurve] {
                let font = lang.isRTL ? NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
                                      : NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
                let text = NSAttributedString(string: L10n.t(key, lang), attributes: [.font: font])
                XCTAssertLessThanOrEqual(text.size().width, 180, "\(lang.rawValue).\(key)")
            }
        }
    }

    func testCoolingModeExplanationsRenderedLines() {
        verifyRenderedLines([.coolingAutomaticHint, .coolingCurveHint, .hardwareUnsupported],
                            dimensions: [(10, [456]), (11, [456])])
    }

    private func verifyRenderedLines(_ keys: [L10nKey], dimensions: [(CGFloat, [CGFloat])]) {
        for lang in AppLanguage.allCases {
            let short = L10n.shortWords(lang).union(lang == .en ? ["an", "the", "of", "to", "in", "on", "for", "with", "from", "without", "through", "and", "or"] : [])
            for (size, widths) in dimensions {
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
