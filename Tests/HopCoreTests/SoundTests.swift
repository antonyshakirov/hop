import XCTest
@testable import HopCore

final class SoundTests: XCTestCase {
    func testKeyboardPercentageSupportsLocalizedDigitsAndSeparateGainLimits() {
        XCTAssertEqual(SoundPercentage.value("75,5 %"), 0.755)
        XCTAssertEqual(SoundPercentage.value("٧٥٫٥٪"), 0.755)
        XCTAssertEqual(SoundPercentage.value("-12"), 0)
        XCTAssertEqual(SoundPercentage.value("200"), 1)
        XCTAssertEqual(SoundPercentage.value("200", maximum: 200), 2)
        XCTAssertEqual(SoundPercentage.value("250", maximum: 200), 2)
        XCTAssertNil(SoundPercentage.value("nan"))
        XCTAssertNil(SoundPercentage.value("1e3"))
        XCTAssertNil(SoundPercentage.value(""))
        XCTAssertNil(SoundPercentage.value("1.2.3"))
    }

    func testVolumePreservesStereoBalanceAndLimitsClipping() throws {
        let quiet = try XCTUnwrap(SoundGain.adjusted([0.4, 0.8], target: 0.3))
        XCTAssertEqual(quiet[0], 0.2, accuracy: 0.0001)
        XCTAssertEqual(quiet[1], 0.4, accuracy: 0.0001)
        let loud = try XCTUnwrap(SoundGain.adjusted([0.2, 0.4], target: 1))
        XCTAssertEqual(loud, [0.5, 1])
        XCTAssertEqual(SoundGain.adjusted([0, 0], target: 0.6), [0.6, 0.6])
        XCTAssertEqual(SoundGain.adjusted([0.2], target: -1), [0])
        XCTAssertNil(SoundGain.adjusted([.nan], target: 0.5))
        XCTAssertNil(SoundGain.adjusted([0.5], target: .infinity))
        XCTAssertNil(SoundGain.adjusted([], target: 0.5))
    }

    func testPartialDeviceWriteRestoresEarlierChannels() {
        enum Failure: Error { case unplugged }
        var hardware = [0.2, 0.6]
        var writes: [Int] = []
        XCTAssertThrowsError(try SoundControlTransaction.apply([0.1, 0.3], originals: hardware) { i, value in
            writes.append(i)
            if i == 1 { throw Failure.unplugged }
            hardware[i] = value
        })
        XCTAssertEqual(hardware, [0.2, 0.6])
        XCTAssertEqual(writes, [0, 1, 0])
    }

    func testMicrophoneLevelRejectsInvalidSamplesAndMapsDecibels() {
        XCTAssertEqual(SoundLevel.normalized(rms: 0), 0)
        XCTAssertEqual(SoundLevel.normalized(rms: .nan), 0)
        XCTAssertEqual(SoundLevel.normalized(rms: .infinity), 0)
        XCTAssertEqual(SoundLevel.normalized(rms: 0.001), 0, accuracy: 0.0001)
        XCTAssertEqual(SoundLevel.normalized(rms: 0.0316227766), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SoundLevel.normalized(rms: 2), 1)
    }
}
