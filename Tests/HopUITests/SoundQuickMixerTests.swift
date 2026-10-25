import AppKit
import SwiftUI
import XCTest
@testable import Hop
import HopCore

@MainActor
final class SoundQuickMixerTests: XCTestCase {
    func testQuickLabelsFitBesideSoundAndSettingsWithoutChangingSize() {
        for language in AppLanguage.allCases {
            let model = AppModel(preview: true)
            let call = SoundCallMixController(enabled: true)
            let controls = NSHostingView(rootView: SoundRowMixerControls(mixer: model.soundMixer, call: call, lang: language, startInput: {})).fittingSize
            let title = NSHostingView(rootView: Text(L10n.t(.soundLabel, language)).font(Theme.mono(11))).fittingSize.width
            XCTAssertLessThanOrEqual(controls.width + title + 94, 368, "Full Sound row: " + language.rawValue)
            for direction: L10nKey in [.soundOutput, .soundInput] {
                func size(_ starting: Bool, _ running: Bool) -> NSSize {
                    NSHostingView(rootView: SoundQuickMixerLabel(direction: direction, starting: starting,
                                                                 running: running, lang: language)).fittingSize
                }
                let off = size(false, false)
                XCTAssertLessThan(off.width, 130, language.rawValue)
                XCTAssertLessThanOrEqual(off.height, 18, "Single line: " + language.rawValue)
                XCTAssertEqual(off.width, size(true, false).width, accuracy: 1, language.rawValue)
                XCTAssertEqual(off.width, size(false, true).width, accuracy: 1, language.rawValue)
                XCTAssertEqual(off.height, size(true, false).height, accuracy: 1, language.rawValue)
                XCTAssertEqual(off.height, size(false, true).height, accuracy: 1, language.rawValue)
            }
        }
    }

    func testQuickInputRequestOpensTheInputPageWithoutCapture() {
        let model = AppModel(preview: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var measured: CGFloat = 0
        window.contentViewController = NSHostingController(rootView: SoundWindowView(sound: model.sound, onHeightChange: { measured = $0 }).environmentObject(model))
        window.orderFront(nil)
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let outputHeight = measured
        model.soundPageRequest = .input
        let deadline = Date().addingTimeInterval(1)
        while (model.soundPageRequest != nil || measured == outputHeight) && Date() < deadline {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertNil(model.soundPageRequest)
        XCTAssertFalse(model.soundCallMix.running)
        XCTAssertFalse(model.soundCallMix.starting)
        XCTAssertFalse(model.soundCallMix.requestingMicrophone)
        XCTAssertFalse(model.sound.checking)
        // Compare measured content rather than the scroll view's viewport/fitting size.
        XCTAssertGreaterThan(outputHeight, 0)
        XCTAssertNotEqual(measured, outputHeight, "The request must switch away from the output content")
    }
}
