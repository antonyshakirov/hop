import XCTest
@testable import HopCore

/// SPEC: docs/spec.md — "Draw over the screen" (hold-to-draw gesture and recorder).
final class HoldGestureTests: XCTestCase {

    private let fnBit: UInt64 = 0x800000
    private let leftControlBit: UInt64 = 0x1
    private let leftOptionBit: UInt64 = 0x20
    private let rightControlBit: UInt64 = 0x2000
    private let leftShiftBit: UInt64 = 0x2
    private let leftCommandBit: UInt64 = 0x8

    private let keyedChord = HoldChord(modifiers: [.leftControl, .leftOption], keyCode: 6)

    private struct Run {
        var state = HoldGesture.State()
        let chord: HoldChord

        mutating func send(_ input: HoldGesture.Input) -> HoldGesture.Step {
            let step = HoldGesture.step(state, chord: chord, input: input)
            state = step.state
            return step
        }

        mutating func flags(_ keyCode: UInt16, _ flags: UInt64) -> HoldGesture.Step {
            send(.flagsChanged(keyCode: keyCode, flags: flags))
        }
    }

    private func holdingStandard() -> Run {
        var run = Run(chord: .standard)
        _ = run.flags(63, fnBit)
        let step = run.flags(59, fnBit | leftControlBit)
        XCTAssertEqual(step.effect, .begin)
        return run
    }

    func testFnThenLeftControlBegins() {
        var run = Run(chord: .standard)
        XCTAssertEqual(run.flags(63, fnBit).effect, .none)
        let step = run.flags(59, fnBit | leftControlBit)
        XCTAssertEqual(step.effect, .begin)
        XCTAssertEqual(step.state.phase, .held)
        XCTAssertFalse(step.swallow)
    }

    func testLeftControlThenFnBegins() {
        var run = Run(chord: .standard)
        XCTAssertEqual(run.flags(59, leftControlBit).effect, .none)
        XCTAssertEqual(run.flags(63, fnBit | leftControlBit).effect, .begin)
    }

    func testReleasingControlReleasesAndPressingItAgainBeginsAgain() {
        var run = holdingStandard()
        let release = run.flags(59, fnBit)
        XCTAssertEqual(release.effect, .release)
        XCTAssertEqual(release.state.phase, .idle)
        XCTAssertEqual(run.flags(59, fnBit | leftControlBit).effect, .begin)
    }

    func testReleasingFnReleases() {
        var run = holdingStandard()
        let step = run.flags(63, leftControlBit)
        XCTAssertEqual(step.effect, .release)
        XCTAssertEqual(step.state.phase, .idle)
    }

    func testAnotherKeyCancelsAndIsNotSwallowed() {
        var run = holdingStandard()
        let step = run.send(.keyDown(123, isRepeat: false))
        XCTAssertEqual(step.effect, .cancel)
        XCTAssertEqual(step.state.phase, .spent)
        XCTAssertFalse(step.swallow)
    }

    func testGlobeKeyDownDoesNotCancel() {
        var run = holdingStandard()
        let step = run.send(.keyDown(179, isRepeat: false))
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(step.state.phase, .held)
    }

    func testExtraModifierCancelsAndChordMustBeLetGoBeforeItBeginsAgain() {
        var run = holdingStandard()
        let cancel = run.flags(56, fnBit | leftControlBit | leftShiftBit)
        XCTAssertEqual(cancel.effect, .cancel)
        XCTAssertEqual(cancel.state.phase, .spent)

        let shiftUp = run.flags(56, fnBit | leftControlBit)
        XCTAssertEqual(shiftUp.effect, .none)
        XCTAssertEqual(shiftUp.state.phase, .spent)

        XCTAssertEqual(run.flags(63, leftControlBit).effect, .none)
        XCTAssertEqual(run.state.phase, .idle)
        XCTAssertEqual(run.flags(59, 0).effect, .none)
        XCTAssertEqual(run.flags(63, fnBit).effect, .none)
        XCTAssertEqual(run.flags(59, fnBit | leftControlBit).effect, .begin)
    }

    func testRightControlDoesNotMatchTheStandardChord() {
        var run = Run(chord: .standard)
        _ = run.flags(63, fnBit)
        let step = run.flags(62, fnBit | rightControlBit)
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(step.state.phase, .idle)
    }

    func testFnBitWithoutAFnKeyEventDoesNotBegin() {
        var run = Run(chord: .standard)
        XCTAssertEqual(run.flags(59, fnBit | leftControlBit).effect, .none)
        XCTAssertEqual(run.state.phase, .idle)
    }

    func testIdleIgnoresKeys() {
        var run = Run(chord: .standard)
        XCTAssertEqual(run.send(.keyDown(0, isRepeat: false)), HoldGesture.Step(state: run.state, effect: .none, swallow: false))
        XCTAssertEqual(run.send(.keyUp(0)).effect, .none)
    }

    func testKeyedChordBeginsSwallowsRepeatsAndReleasesOnKeyUp() {
        var run = Run(chord: keyedChord)
        _ = run.flags(59, leftControlBit)
        XCTAssertEqual(run.flags(58, leftControlBit | leftOptionBit).effect, .none)

        let down = run.send(.keyDown(6, isRepeat: false))
        XCTAssertEqual(down.effect, .begin)
        XCTAssertTrue(down.swallow)
        XCTAssertTrue(down.state.swallowsChordKey)

        let repeated = run.send(.keyDown(6, isRepeat: true))
        XCTAssertEqual(repeated.effect, .none)
        XCTAssertTrue(repeated.swallow)

        let up = run.send(.keyUp(6))
        XCTAssertEqual(up.effect, .release)
        XCTAssertEqual(up.state.phase, .idle)
        XCTAssertTrue(up.swallow)
        XCTAssertFalse(up.state.swallowsChordKey)
    }

    func testKeyedChordModifierReleasedFirstSwallowsThePendingKeyUpOnce() {
        var run = Run(chord: keyedChord)
        _ = run.flags(59, leftControlBit)
        _ = run.flags(58, leftControlBit | leftOptionBit)
        XCTAssertEqual(run.send(.keyDown(6, isRepeat: false)).effect, .begin)

        let optionUp = run.flags(58, leftControlBit)
        XCTAssertEqual(optionUp.effect, .release)
        XCTAssertEqual(optionUp.state.phase, .idle)
        XCTAssertTrue(optionUp.state.swallowsChordKey)

        XCTAssertTrue(run.send(.keyDown(6, isRepeat: true)).swallow)

        let pendingUp = run.send(.keyUp(6))
        XCTAssertEqual(pendingUp.effect, .none)
        XCTAssertTrue(pendingUp.swallow)
        XCTAssertFalse(pendingUp.state.swallowsChordKey)

        XCTAssertFalse(run.send(.keyUp(6)).swallow)
    }

    func testKeyedChordNeedsTheExactModifiers() {
        var run = Run(chord: keyedChord)
        _ = run.flags(59, leftControlBit)
        let step = run.send(.keyDown(6, isRepeat: false))
        XCTAssertEqual(step.effect, .none)
        XCTAssertFalse(step.swallow)
    }

    func testKeyedChordExtraModifierCancels() {
        var run = Run(chord: keyedChord)
        _ = run.flags(59, leftControlBit)
        _ = run.flags(58, leftControlBit | leftOptionBit)
        _ = run.send(.keyDown(6, isRepeat: false))
        let step = run.flags(55, leftControlBit | leftOptionBit | leftCommandBit)
        XCTAssertEqual(step.effect, .cancel)
        XCTAssertEqual(step.state.phase, .spent)
    }

    func testKeyedChordAnotherKeyCancelsAndIsNotSwallowed() {
        var run = Run(chord: keyedChord)
        _ = run.flags(59, leftControlBit)
        _ = run.flags(58, leftControlBit | leftOptionBit)
        _ = run.send(.keyDown(6, isRepeat: false))
        let step = run.send(.keyDown(7, isRepeat: false))
        XCTAssertEqual(step.effect, .cancel)
        XCTAssertEqual(step.state.phase, .spent)
        XCTAssertFalse(step.swallow)
    }

    func testRecorderRecordsModifiersOnlyChordWhenAllAreLetGo() {
        var recorder = HoldRecorder()
        XCTAssertEqual(recorder.flagsChanged(keyCode: 63, flags: fnBit), .waiting)
        XCTAssertEqual(recorder.flagsChanged(keyCode: 59, flags: fnBit | leftControlBit), .waiting)
        XCTAssertEqual(recorder.flagsChanged(keyCode: 63, flags: leftControlBit), .waiting)
        XCTAssertEqual(recorder.flagsChanged(keyCode: 59, flags: 0), .recorded(.standard))
    }

    func testRecorderIgnoresASingleModifier() {
        var recorder = HoldRecorder()
        XCTAssertEqual(recorder.flagsChanged(keyCode: 56, flags: leftShiftBit), .waiting)
        XCTAssertEqual(recorder.flagsChanged(keyCode: 56, flags: 0), .waiting)
        XCTAssertEqual(recorder.flagsChanged(keyCode: 59, flags: leftControlBit), .waiting)
        XCTAssertEqual(recorder.flagsChanged(keyCode: 58, flags: leftControlBit | leftOptionBit), .waiting)
        XCTAssertEqual(recorder.flagsChanged(keyCode: 58, flags: leftControlBit), .waiting)
        XCTAssertEqual(
            recorder.flagsChanged(keyCode: 59, flags: 0),
            .recorded(HoldChord(modifiers: [.leftControl, .leftOption]))
        )
    }

    func testRecorderRecordsModifiersWithAKeyAndThenStaysQuiet() {
        var recorder = HoldRecorder()
        _ = recorder.flagsChanged(keyCode: 55, flags: leftCommandBit)
        _ = recorder.flagsChanged(keyCode: 56, flags: leftCommandBit | leftShiftBit)
        XCTAssertEqual(
            recorder.keyDown(40),
            .recorded(HoldChord(modifiers: [.leftCommand, .leftShift], keyCode: 40))
        )
        XCTAssertEqual(recorder.flagsChanged(keyCode: 56, flags: leftCommandBit), .waiting)
        XCTAssertEqual(recorder.flagsChanged(keyCode: 55, flags: 0), .waiting)
    }

    func testRecorderIgnoresAKeyWithoutModifiers() {
        var recorder = HoldRecorder()
        XCTAssertEqual(recorder.keyDown(40), .waiting)
    }

    func testRecorderIgnoresModifierKeyDowns() {
        var recorder = HoldRecorder()
        _ = recorder.flagsChanged(keyCode: 55, flags: leftCommandBit)
        XCTAssertEqual(recorder.keyDown(179), .waiting)
    }

    func testEscapeCancelsRecordingAndLaterEventsWait() {
        var recorder = HoldRecorder()
        _ = recorder.flagsChanged(keyCode: 55, flags: leftCommandBit)
        XCTAssertEqual(recorder.keyDown(53), .cancelled)
        XCTAssertEqual(recorder.keyDown(40), .waiting)
        XCTAssertEqual(recorder.flagsChanged(keyCode: 55, flags: 0), .waiting)
    }

    func testAPendingChordKeyIsSwallowedOnlyWithTheChordModifiersStillHeld() {
        var run = Run(chord: keyedChord)
        _ = run.flags(59, leftControlBit)
        _ = run.flags(58, leftControlBit | leftOptionBit)
        _ = run.send(.keyDown(6, isRepeat: false))
        _ = run.flags(58, leftControlBit)
        _ = run.flags(59, 0)
        let bare = run.send(.keyDown(6, isRepeat: false))
        XCTAssertFalse(bare.swallow)
        XCTAssertFalse(bare.state.swallowsChordKey)
    }

    func testHeldLayerIsReleasedWhenTheChordIsFoundNotHeld() {
        var run = holdingStandard()
        let step = run.send(.chordNotHeld)
        XCTAssertEqual(step.effect, .release)
        XCTAssertEqual(step.state, HoldGesture.State())
    }

    func testChordNotHeldWhileIdleDoesNothing() {
        var run = Run(chord: .standard)
        XCTAssertEqual(run.send(.chordNotHeld).effect, .none)
    }
}
