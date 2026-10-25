import AppKit
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class SoundWindowLayoutTests: XCTestCase {
    private final class MixSession: SoundCallSession {
        var microphoneMuteChanged: ((Bool) -> Void)?
        func setMicrophoneMuted(_ value: Bool) -> Bool { true }
        var complete: ((Result<Void, SoundFailure>) -> Void)?
        func start(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) { complete = completed }
        func update(_ configuration: SoundCallConfiguration) {}
        func stop() {}
        func shutdown() {}
    }

    func testMixerHeightStaysFixedAcrossStoppedStartingAndRunning() {
        let model = AppModel(preview: true)
        for language in AppLanguage.allCases {
            for width: CGFloat in [360, 480] {
                let session = MixSession()
                let call = SoundCallMixController(enabled: true, session: session, access: { $0(true) })
                let host = NSHostingView(rootView: SoundCallMixView(call: call, sound: model.sound, mixer: model.soundMixer, lang: language).frame(width: width))
                func height() -> CGFloat {
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                    return host.fittingSize.height
                }
                let stopped = height()
                call.open(); call.start(inputUID: "fixture-mic", apps: [])
                XCTAssertEqual(height(), stopped, accuracy: 1, "Starting: \(language.rawValue), \(width)")
                session.complete?(.success(()))
                XCTAssertEqual(height(), stopped, accuracy: 1, "Running: \(language.rawValue), \(width)")
                call.close()
                XCTAssertEqual(height(), stopped, accuracy: 1, "Stopped again: \(language.rawValue), \(width)")
            }
        }
    }

    func testStandardZoomIsAUserSizeWithoutLiveDragging() {
        let window = NSWindow(contentRect: NSRect(x: 400, y: 200, width: 520, height: 300),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let expected = window.contentRect(forFrameRect: window.frame).height
        window.orderFront(nil)
        defer { window.close() }
        window.zoom(nil)
        let expanded = window.contentRect(forFrameRect: window.frame).height
        XCTAssertGreaterThan(expanded, expected)
        XCTAssertFalse(window.inLiveResize)
        XCTAssertTrue(SoundWindowLayout.isUserResize(contentHeight: expanded, expectedHeight: expected),
            "Standard Zoom must disable content fitting even outside a drag")
        XCTAssertFalse(SoundWindowLayout.isUserResize(contentHeight: expected, expectedHeight: expected),
            "An acknowledged automatic resize must leave fitting enabled")
    }

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

    func testSoundOutputDoesNotReserveHiddenInputHeight() {
        let model = AppModel(preview: true)
        let host = NSHostingView(rootView: SoundWindowView(sound: model.sound).environmentObject(model))
        host.frame.size = NSSize(width: 520, height: 320)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 200)
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
