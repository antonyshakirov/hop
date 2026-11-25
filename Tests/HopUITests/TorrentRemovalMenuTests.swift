import AppKit
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class TorrentRemovalMenuTests: XCTestCase {
    private let rowWidth: CGFloat = 312

    func testTheThreeChoicesShareOneColourOnOneLine() throws {
        let defaults = UserDefaults.standard
        let savedTheme = defaults.object(forKey: Theme.themeKey)
        defer {
            if let savedTheme { defaults.set(savedTheme, forKey: Theme.themeKey) }
            else { defaults.removeObject(forKey: Theme.themeKey) }
        }
        for (lang, dark) in [(AppLanguage.ru, false), (.ru, true), (.en, false)] {
            defaults.set(dark ? "dark" : "light", forKey: Theme.themeKey)
            let bitmap = try render(menu(lang).frame(width: rowWidth).padding(12).background(Theme.background)
                .environment(\.colorScheme, dark ? .dark : .light))
            XCTAssertLessThanOrEqual(bitmap.size.height, 24 + 20, "one compact line")
            if let path = ProcessInfo.processInfo.environment["HOP_TORRENT_RENDER_DIR"],
               let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: path)
                    .appendingPathComponent("torrent-remove-\(lang.rawValue)-\(dark ? "dark" : "light").png"))
            }
            var warm = 0
            for x in 0..<bitmap.pixelsWide { for y in 0..<bitmap.pixelsHigh {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.redComponent - max(c.greenComponent, c.blueComponent) > 0.25 { warm += 1 }
            } }
            XCTAssertEqual(warm, 0, "no choice is painted as the dangerous default")
        }
    }

    func testEveryLanguageFitsTheRowWithoutShrinking() throws {
        for lang in AppLanguage.allCases {
            let host = NSHostingView(rootView: menu(lang).fixedSize())
            XCTAssertLessThanOrEqual(host.fittingSize.width, rowWidth, "\(lang.rawValue) labels overflow the row")
        }
    }

    private func menu(_ lang: AppLanguage) -> some View {
        TorrentRemovalMenu(lang: lang, sourceAvailable: true, choose: { _ in }, cancel: {})
            .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)
    }

    private func render(_ view: some View) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.setFrameSize(size); window.setContentSize(size); host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }
}
