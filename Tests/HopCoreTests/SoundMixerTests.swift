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
    func testNeutralChannelsDoNotRequireProcessing() {
        XCTAssertFalse(SoundMixerActivity.requiresProcessing(apps: [.init(), .init()], inputs: [.init()]))
        XCTAssertFalse(SoundMixerActivity.requiresProcessing(apps: [], inputs: []))
    }
    func testAppVolumeAndMuteRequireProcessing() {
        for gain in [0.0, 0.7, 1.4, 2.0] {
            var app = SoundChannelSettings(); app.gain = gain
            XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [app], inputs: [.init()]))
        }
        var app = SoundChannelSettings(); app.muted = true
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [app], inputs: [.init()]))
    }
    func testEveryRemainingInputEffectKeepsProcessing() {
        var input = SoundChannelSettings()
        input.bass = true
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input]))
        input.bass = false; input.muted = true
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input]))
        input.muted = false; input.gain = 1.5
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input]))
    }
    func testDisabledInputEffectsDoNotKeepTheMixerRunning() {
        var disabled = SoundChannelSettings()
        disabled.active = false; disabled.bass = true; disabled.muted = true; disabled.gain = 2
        XCTAssertFalse(SoundMixerActivity.requiresProcessing(apps: [.init()], inputs: [.init(), disabled]))
    }
    func testCombiningInputsNeedsProcessing() {
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [], inputs: [.init(), .init()]))
    }
    func testRestoringLastGainToUnityStopsProcessing() {
        var input = SoundChannelSettings(); input.gain = 1.4
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input]))
        input.gain = 1
        XCTAssertFalse(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input]))
        input.gain = 1.0000001
        XCTAssertFalse(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input]))
        input.gain = .nan
        XCTAssertFalse(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input]))
    }
}
