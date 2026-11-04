import AppKit
import CoreText
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class TrackerReleaseTypographyTests: XCTestCase {
    func testPreparedNotesWrapWithoutHangingWordsInEveryLanguage() {
        for lang in AppLanguage.allCases {
            let current = L10n.t(.docNews, lang).components(separatedBy: "2.4.2 – ")[0]
            var short = L10n.shortWords(lang)
            if lang == .en { short.formUnion(["the", "and", "of", "to", "in", "for", "into", "or"]) }
            let font = lang.isRTL ? NSFont.systemFont(ofSize: 12, weight: .medium)
                : NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            for width in [280.0, 324.0, 432.0, 640.0] {
                for paragraph in current.components(separatedBy: "\n\n") where !paragraph.isEmpty {
                    let text = paragraph.hasPrefix("• ") ? String(paragraph.dropFirst(2)) : paragraph
                    let lines = renderedLines(text, width: width, font: font)
                    XCTAssertFalse(lines.isEmpty, lang.rawValue)
                    for line in lines.dropLast() {
                        let last = line.components(separatedBy: .whitespaces).last ?? ""
                        XCTAssertFalse(short.contains(last.lowercased()), "\(lang.rawValue) \(width): \(line)")
                    }
                    for line in lines {
                        XCTAssertFalse(line.hasPrefix("—") || line.hasPrefix("–"),
                                       "\(lang.rawValue) \(width): \(line)")
                    }
                }
            }
        }
    }

    func testPreparedNotesRenderInBothThemes() throws {
        let directory = ProcessInfo.processInfo.environment["HOP_PATCH_RENDER_DIR"]
        if let directory {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        let savedTheme = UserDefaults.standard.object(forKey: Theme.themeKey)
        defer {
            if let savedTheme { UserDefaults.standard.set(savedTheme, forKey: Theme.themeKey) }
            else { UserDefaults.standard.removeObject(forKey: Theme.themeKey) }
        }
        for lang in [AppLanguage.en, .ru, .de, .fr] {
            let text = L10n.t(.docNews, lang).components(separatedBy: "2.4.2 – ")[0]
            for dark in [false, true] {
                UserDefaults.standard.set(dark ? "dark" : "light", forKey: Theme.themeKey)
                let view = NSHostingView(rootView: DocView(text: text)
                    .padding(20).frame(width: 368)
                    .background(Theme.background)
                    .environment(\.colorScheme, dark ? .dark : .light))
                view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                view.frame.size = view.fittingSize
                view.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                XCTAssertEqual(view.bounds.width, 368)
                XCTAssertGreaterThan(view.bounds.height, 60)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let name = "2.4.3-\(lang.rawValue)-\(dark ? "dark" : "light").png"
                if let directory {
                    try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
                }
            }
        }
    }

    private func renderedLines(_ text: String, width: Double, font: NSFont) -> [String] {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 1000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        return (CTFrameGetLines(frame) as! [CTLine]).map { line in
            let range = CTLineGetStringRange(line)
            return (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
