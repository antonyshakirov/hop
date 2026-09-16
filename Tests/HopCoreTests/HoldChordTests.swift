import XCTest
@testable import HopCore

/// SPEC: docs/spec.md — "Draw over the screen" (hold-to-draw chord model).
final class HoldChordTests: XCTestCase {


    func testFnThenLeftOptionInOrder() {
        let afterFn = HoldModifiers.next(after: [], keyCode: 63, flags: 0x800000)
        XCTAssertEqual(afterFn, [.fn])

        let afterOption = HoldModifiers.next(after: afterFn, keyCode: 58, flags: 0x800000 | 0x20)
        XCTAssertEqual(afterOption, [.fn, .leftOption])
    }

    func testLeftOptionBeforeFnStillCarriesBothOnce() {
        let afterOptionOnly = HoldModifiers.next(after: [], keyCode: 58, flags: 0x800000 | 0x20)
        XCTAssertEqual(afterOptionOnly, [.leftOption], "fn bit is ignored on a non-fn keyCode")
    }

    func testRightOptionIsCarriedWithFn() {
        let result = HoldModifiers.next(after: [.fn], keyCode: 61, flags: 0x40)
        XCTAssertEqual(result, [.fn, .rightOption])
    }

    func testFnKeyUpDropsOnlyFn() {
        let result = HoldModifiers.next(after: [.fn, .leftOption], keyCode: 63, flags: 0x20)
        XCTAssertEqual(result, [.leftOption])
    }


    func testGlobeIsAModifierKeyButAnOrdinaryLetterIsNot() {
        XCTAssertTrue(HoldModifiers.isModifierKey(179))
        XCTAssertFalse(HoldModifiers.isModifierKey(6))
    }

    func testOfKeyCodeMapsKnownModifiersAndNilsOtherwise() {
        XCTAssertEqual(HoldModifiers.of(keyCode: 58), .leftOption)
        XCTAssertNil(HoldModifiers.of(keyCode: 0))
    }


    func testStandardChordIsValid() {
        XCTAssertTrue(HoldChord.standard.isValid)
    }

    func testASingleModifierWithNoKeyIsInvalid() {
        XCTAssertFalse(HoldChord(modifiers: [.leftShift]).isValid)
    }

    func testAModifierPlusAnOrdinaryKeyIsValid() {
        XCTAssertTrue(HoldChord(modifiers: [.leftCommand], keyCode: 40).isValid)
    }

    func testAKeyWithNoModifierIsInvalid() {
        XCTAssertFalse(HoldChord(modifiers: [], keyCode: 40).isValid)
    }

    func testAKeyThatIsItselfAModifierKeyIsInvalid() {
        XCTAssertFalse(HoldChord(modifiers: [.fn], keyCode: 58).isValid)
    }


    func testStorageRoundTripsForStandard() {
        XCTAssertEqual(HoldChord(storage: HoldChord.standard.storage), HoldChord.standard)
    }

    func testStorageRoundTripsForModifiersPlusKey() {
        let chord = HoldChord(modifiers: [.leftCommand, .leftShift], keyCode: 40)
        XCTAssertEqual(HoldChord(storage: chord.storage), chord)
    }

    func testStorageRejectsAnInvalidChord() {
        XCTAssertNil(HoldChord(storage: "leftShift"))
    }

    func testStandardChordIsFnAndLeftControl() {
        XCTAssertEqual(HoldChord.standard, HoldChord(modifiers: [.fn, .leftControl]))
        XCTAssertEqual(HoldChord.standard.storage, "fn+leftControl")
    }

    func testStorageRejectsGarbage() {
        XCTAssertNil(HoldChord(storage: "garbage"))
    }

    func testStorageRejectsRepeatedModifiers() {
        XCTAssertNil(HoldChord(storage: "fn+fn+leftOption"))
    }

    func testStandardDisplaysAsFnControl() {
        XCTAssertEqual(HoldChord.standard.display(keyName: { _ in "K" }), "fn ⌃")
    }

    func testRightSideGetsAnRPrefixAndKeyNameComesLast() {
        let chord = HoldChord(modifiers: [.rightOption, .leftCommand], keyCode: 40)
        XCTAssertEqual(chord.display(keyName: { _ in "K" }), "R⌥ ⌘ K")
    }


    func testCarbonModifiersIsNilWithoutAKey() {
        XCTAssertNil(HoldChord.standard.carbonModifiers)
    }

    func testCarbonModifiersCombinesCommandAndShift() {
        let chord = HoldChord(modifiers: [.leftCommand, .leftShift], keyCode: 40)
        XCTAssertEqual(chord.carbonModifiers, 0x300)
    }
}
