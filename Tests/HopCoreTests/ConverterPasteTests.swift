import XCTest
@testable import HopCore

final class ConverterPasteTests: XCTestCase {
    // The converter window is the paste target and already key — normal case.
    func testVisibleAndKeyIngests() {
        XCTAssertTrue(ConverterPaste.shouldIngest(
            windowVisible: true, windowIsKey: true, hasKeyWindow: true))
    }

    // The reproduced bug: opened from the background, activation still settling,
    // so no window has claimed key yet. The plain key-equivalent route drops the
    // paste here; the monitor must ingest it.
    func testVisibleButNoKeyWindowIngests() {
        XCTAssertTrue(ConverterPaste.shouldIngest(
            windowVisible: true, windowIsKey: false, hasKeyWindow: false))
    }

    // Another Hop window owns key (e.g. settings with a text field): ⌘V belongs
    // to that window and must NOT be stolen by the converter.
    func testAnotherWindowKeyDoesNotSteal() {
        XCTAssertFalse(ConverterPaste.shouldIngest(
            windowVisible: true, windowIsKey: false, hasKeyWindow: true))
    }

    // Converter closed: never ingest, regardless of key state.
    func testNotVisibleNeverIngests() {
        XCTAssertFalse(ConverterPaste.shouldIngest(
            windowVisible: false, windowIsKey: false, hasKeyWindow: false))
        XCTAssertFalse(ConverterPaste.shouldIngest(
            windowVisible: false, windowIsKey: true, hasKeyWindow: true))
    }
}
