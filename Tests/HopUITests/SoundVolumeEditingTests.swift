import XCTest
@testable import Hop

final class SoundVolumeEditingTests: XCTestCase {
    func testDraggingReplacesFocusedPercentageAndFocusLossDoesNotReplayIt() {
        var state = SoundVolumeEditing(value: 0)
        state.begin()
        state.text = "0"
        state.drag(to: 0.3)
        XCTAssertEqual(state.value, 0.3)
        XCTAssertEqual(state.text, "30")
        XCTAssertNil(state.commit(maximum: 1))
        XCTAssertEqual(state.value, 0.3)
        XCTAssertEqual(state.text, "30")
    }

    func testChangedKeyboardValueCommitsAndEscapeRestoresTheCurrentValue() {
        var state = SoundVolumeEditing(value: 0.3)
        state.begin()
        state.text = "46"
        XCTAssertEqual(state.commit(maximum: 1), 0.46)
        state.begin()
        state.text = "0"
        state.cancel()
        XCTAssertNil(state.commit(maximum: 1))
        XCTAssertEqual(state.text, "46")
    }

    func testUnchangedFocusPreservesExactHardwareValueAndInvalidInputIsIgnored() {
        var state = SoundVolumeEditing(value: 0.4567)
        state.begin()
        XCTAssertNil(state.commit(maximum: 1))
        XCTAssertEqual(state.value, 0.4567)
        state.begin()
        state.text = "invalid"
        XCTAssertNil(state.commit(maximum: 1))
        XCTAssertEqual(state.value, 0.4567)
        XCTAssertEqual(state.text, "46")
        state.reflect(0.6)
        XCTAssertEqual(state.text, "60")
    }
}
