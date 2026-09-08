import XCTest
@testable import HopCore

final class MarkupInkBookTests: XCTestCase {
    private func standard(_ tool: MarkupTool) -> MarkupInk {
        switch tool {
        case .marker: return MarkupInk(hex: "#FFD60A", width: 18)
        case .text: return MarkupInk(hex: "#FF453A", width: 18)
        default: return MarkupInk(hex: "#FF453A", width: 4)
        }
    }

    func testEachToolKeepsItsOwnColourWhileNothingIsShared() {
        var book = MarkupInkBook()
        book.set(MarkupInk(hex: "#00FF00", width: 4), for: .pencil, standard: standard)
        XCTAssertEqual(book.ink(for: .pencil, standard: standard).hex, "#00FF00")
        XCTAssertEqual(book.ink(for: .marker, standard: standard).hex, "#FFD60A")
    }

    func testASharedColourReachesEveryToolAndLeavesTheWidthsAlone() {
        var book = MarkupInkBook(shared: true, common: "#FF453A")
        book.set(MarkupInk(hex: "#0A84FF", width: 4), for: .pencil, standard: standard)
        XCTAssertEqual(book.ink(for: .marker, standard: standard).hex, "#0A84FF")
        XCTAssertEqual(book.ink(for: .marker, standard: standard).width, 18)
        XCTAssertEqual(book.ink(for: .text, standard: standard).width, 18)
        XCTAssertEqual(book.ink(for: .pencil, standard: standard).width, 4)
    }

    /// Turned on, the colour in hand is the one that spreads.
    func testSharingStartsFromTheColourOfTheToolInHand() {
        var book = MarkupInkBook()
        book.set(MarkupInk(hex: "#FFD60A", width: 18), for: .marker, standard: standard)
        book.share(true, from: .marker, standard: standard)
        XCTAssertEqual(book.ink(for: .pencil, standard: standard).hex, "#FFD60A")
        XCTAssertEqual(book.ink(for: .pencil, standard: standard).width, 4)
    }

    /// Turned off, nothing jumps: every tool keeps what it was drawing with and
    /// only drifts apart from there.
    func testUnsharingKeepsTheColourEveryToolAlreadyHad() {
        var book = MarkupInkBook(shared: true, common: "#0A84FF")
        book.share(false, from: .pencil, standard: standard)
        XCTAssertEqual(book.ink(for: .marker, standard: standard).hex, "#0A84FF")
        book.set(MarkupInk(hex: "#30D158", width: 4), for: .pencil, standard: standard)
        XCTAssertEqual(book.ink(for: .pencil, standard: standard).hex, "#30D158")
        XCTAssertEqual(book.ink(for: .marker, standard: standard).hex, "#0A84FF")
    }

    func testSettingTheSameSideOfTheSwitchChangesNothing() {
        var book = MarkupInkBook()
        book.set(MarkupInk(hex: "#00FF00", width: 4), for: .pencil, standard: standard)
        book.share(false, from: .pencil, standard: standard)
        XCTAssertEqual(book.ink(for: .marker, standard: standard).hex, "#FFD60A")
    }
}
