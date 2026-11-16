import AppKit
import CoreText
import HopCore
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class AwakeLidFailurePresentationTests: XCTestCase {
    func testBusyReasonWrapsAndRendersBelowAwakeInEveryLanguage() throws {
        let saved = UserDefaults.standard.object(forKey: Theme.themeKey)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: Theme.themeKey) }
            else { UserDefaults.standard.removeObject(forKey: Theme.themeKey) }
        }
        for lang in AppLanguage.allCases {
            let text = HangingWords.glued(L10n.t(.hardwareBusy, lang),
                shortWords: L10n.shortWords(lang), trailing: L10n.trailingWords(lang))
            let font = lang.isRTL ? NSFont.systemFont(ofSize: 10, weight: .medium)
                : NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
            for width in [280.0, 320.0] {
                let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                    CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 1000), transform: nil), nil)
                let range = CTFrameGetVisibleStringRange(frame)
                XCTAssertEqual(range.length, (text as NSString).length, lang.rawValue)
                let lines = CTFrameGetLines(frame) as! [CTLine]
                XCTAssertGreaterThan(lines.count, 0)
                XCTAssertLessThanOrEqual(lines.count, 6, lang.rawValue)
                for line in lines.dropLast() {
                    let r = CTLineGetStringRange(line)
                    let value = (text as NSString).substring(with: NSRange(location: r.location, length: r.length))
                    let last = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: " ").last?.lowercased() ?? ""
                    XCTAssertFalse(L10n.shortWords(lang).contains(last), "\(lang.rawValue): \(value)")
                }
            }
            for dark in [false, true] {
                UserDefaults.standard.set(dark ? "dark" : "light", forKey: Theme.themeKey)
                let renderer = ImageRenderer(content: AwakeLidFailureView(reason: .busy, lang: lang)
                    .frame(width: 320).padding(12).background(Theme.background)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                XCTAssertEqual(image.size.width, 344)
                XCTAssertLessThan(image.size.height, 110, lang.rawValue)
                if [.en, .ru, .de, .fr, .ar].contains(lang),
                   let directory = ProcessInfo.processInfo.environment["HOP_HOVER_RENDER_DIR"] {
                    let url = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                    try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                        .write(to: url.appendingPathComponent("lid-\(lang.rawValue)-\(dark ? "dark" : "light").png"))
                }
            }
        }
    }
}
