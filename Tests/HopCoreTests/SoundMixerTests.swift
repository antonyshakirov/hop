import XCTest
@testable import HopCore

final class SoundMixerTests: XCTestCase {
    func testLegacySettingsPreserveControlsAndDiscardNoiseSuppression() throws {
        let data = Data(#"{"input:mic":{"gain":1.4,"muted":true,"denoise":true,"bass":true,"active":false}}"#.utf8)
        let saved = try JSONDecoder().decode([String: SoundChannelSettings].self, from: data)
        let input = try XCTUnwrap(saved["input:mic"])
        XCTAssertEqual(input.gain, 1.4)
        XCTAssertTrue(input.muted)
        XCTAssertTrue(input.bass)
        XCTAssertFalse(input.active)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: [String: Any]]
        XCTAssertNil(encoded["input:mic"]?["denoise"])
    }
}
