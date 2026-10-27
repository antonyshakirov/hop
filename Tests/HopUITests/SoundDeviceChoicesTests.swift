import AppKit
import SwiftUI
import XCTest
@testable import Hop
import HopCore

@MainActor
final class SoundDeviceChoicesTests: XCTestCase {
    func testApplicationDeviceListFitsItsActualRowsAndCapsLongLists() {
        for count in [0, 1, 3, 25] {
            check(count: count, missing: false, lang: .en)
        }
    }

    func testWrappedUnavailableDeviceFitsInBothLayoutDirections() {
        for language: AppLanguage in [.ru, .ar] {
            check(count: 2, missing: true, lang: language)
        }
    }

    func testOverflowCanScrollAllTheWayToTheLastSource() throws {
        let view = SoundDeviceChoices {
            VStack(spacing: 4) {
                ForEach(0..<25, id: \.self) { index in
                    Text("Device \(index)").font(Theme.mono(11)).padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(8)
        }
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        let scroll = try XCTUnwrap(scrollView(in: host))
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertEqual(host.bounds.height, 320, accuracy: 1)
        XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height)
        let end = document.bounds.maxY - scroll.contentView.bounds.height
        scroll.contentView.scroll(to: NSPoint(x: 0, y: end))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertEqual(scroll.contentView.bounds.maxY, document.bounds.maxY, accuracy: 1,
                       "The height cap must leave the final source reachable")
    }

    private func check(count: Int, missing: Bool, lang: AppLanguage, file: StaticString = #filePath, line: UInt = #line) {
        let defaults = UserDefaults(suiteName: "SoundDeviceChoicesTests.\(UUID().uuidString)")!
        let devices = (0..<count).map { index in
            SoundDevice(uid: "fixture-\(index)", name: "Output \(index)", volume: 1,
                        muted: false, canChangeVolume: true, canMute: true)
        }
        let mixer = SoundMixerController(defaults: defaults, discover: { [] }, outputs: { devices })
        mixer.open()
        defer { mixer.close() }
        let channel = SoundMixerChannel(id: "fixture.app", name: "Fixture", input: false, settings: .init())
        if missing {
            channel.preference.outputUID = "missing"
            channel.preference.outputName = "A previously selected audio device with a long name that wraps onto additional lines"
        }
        let row = SoundMixerChannelRow(channel: channel, mixer: mixer, lang: lang)
        let natural = NSHostingView(rootView: row.outputChoiceContent.frame(width: 300)
            .fixedSize(horizontal: false, vertical: true)).fittingSize
        let actual = NSHostingView(rootView: row.outputChoices).fittingSize
        XCTAssertEqual(actual.width, 300, accuracy: 1, file: file, line: line)
        XCTAssertEqual(actual.height, min(320, natural.height), accuracy: 1,
                       "\(count) devices, missing=\(missing), \(lang.rawValue)", file: file, line: line)
        if count == 25 { XCTAssertGreaterThan(natural.height, actual.height, file: file, line: line) }
    }
}
