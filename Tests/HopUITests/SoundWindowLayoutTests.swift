import AppKit
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class SoundWindowLayoutTests: XCTestCase {
    func testOpeningCentersFinalSizeAndUsesAvailableHeight() {
        let visible = CGRect(x: 1470, y: 50, width: 1470, height: 800)
        let current = CGRect(x: 100, y: 100, width: 520, height: 348)
        let frame = SoundWindowLayout.frame(current: current, contentHeight: 1000, chromeHeight: 28,
                                           visible: visible, centered: true)
        XCTAssertEqual(frame.midX, visible.midX)
        XCTAssertEqual(frame.midY, visible.midY)
        XCTAssertEqual(frame.height, 768)
        XCTAssertTrue(visible.contains(frame))
        let shorter = SoundWindowLayout.frame(current: frame, contentHeight: 560, chromeHeight: 28,
                                             visible: visible, centered: false)
        XCTAssertEqual(shorter.maxY, frame.maxY)
        XCTAssertEqual(shorter.height, 588)
    }

    func testMuteLabelsKeepTheSameWidthInEveryLanguage() {
        for lang in AppLanguage.allCases {
            for input in [false, true] {
                func size(_ muted: Bool) -> NSSize {
                    NSHostingView(rootView: SoundMuteLabel(muted: muted, input: input, lang: lang)
                        .font(Theme.mono(11))).fittingSize
                }
                XCTAssertEqual(size(true), size(false), lang.rawValue)
            }
        }
    }

    func testMainSoundWindowIsCompactWithoutInputChannels() {
        let model = AppModel(preview: true)
        let host = NSHostingView(rootView: SoundWindowView(sound: model.sound).environmentObject(model))
        host.frame.size = NSSize(width: 520, height: 320)
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.height, 400)
    }

    func testScrollableSoundContentReportsItsFullHeight() {
        let model = AppModel(preview: true)
        var measured: CGFloat = 0
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: SoundWindowView(sound: model.sound) { measured = $0 }
            .environmentObject(model))
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 520, height: 320))
        window.orderFront(nil)
        defer { window.close() }
        let deadline = Date().addingTimeInterval(1)
        while measured < 200 && Date() < deadline {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertGreaterThan(measured, 200, "Scrollable content must report its full height, rather than zero or the viewport")
    }
}
