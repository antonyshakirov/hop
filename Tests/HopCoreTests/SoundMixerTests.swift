import XCTest
@testable import HopCore

final class SoundMixerTests: XCTestCase {
    func testNeutralChannelsDoNotRequireProcessing() {
        XCTAssertFalse(SoundMixerActivity.requiresProcessing(apps: [.init(), .init()], inputs: [.init()], denoiseAll: false))
        XCTAssertFalse(SoundMixerActivity.requiresProcessing(apps: [], inputs: [], denoiseAll: false))
    }
    func testAppVolumeAndMuteSurviveDisablingDenoise() {
        for gain in [0.0, 0.7, 1.4, 2.0] {
            var app = SoundChannelSettings(); app.gain = gain
            XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [app], inputs: [.init()], denoiseAll: false))
        }
        var app = SoundChannelSettings(); app.muted = true
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [app], inputs: [.init()], denoiseAll: false))
    }
    func testEveryRemainingInputEffectKeepsProcessing() {
        var input = SoundChannelSettings()
        input.bass = true
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input], denoiseAll: false))
        input.bass = false; input.denoise = true
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input], denoiseAll: false))
        input.denoise = false; input.muted = true
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input], denoiseAll: false))
        input.muted = false; input.gain = 1.5
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input], denoiseAll: false))
    }
    func testDisabledInputEffectsDoNotKeepTheMixerRunning() {
        var disabled = SoundChannelSettings()
        disabled.active = false; disabled.bass = true; disabled.denoise = true; disabled.muted = true; disabled.gain = 2
        XCTAssertFalse(SoundMixerActivity.requiresProcessing(apps: [.init()], inputs: [.init(), disabled], denoiseAll: false))
    }
    func testCombiningInputsAndGlobalDenoiseNeedProcessing() {
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [], inputs: [.init(), .init()], denoiseAll: false))
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [], inputs: [.init()], denoiseAll: true))
        XCTAssertFalse(SoundMixerActivity.requiresProcessing(apps: [], inputs: [], denoiseAll: true))
    }
    func testRestoringLastGainToUnityStopsProcessing() {
        var input = SoundChannelSettings(); input.gain = 1.4
        XCTAssertTrue(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input], denoiseAll: false))
        input.gain = 1
        XCTAssertFalse(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input], denoiseAll: false))
        input.gain = 1.0000001
        XCTAssertFalse(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input], denoiseAll: false))
        input.gain = .nan
        XCTAssertFalse(SoundMixerActivity.requiresProcessing(apps: [], inputs: [input], denoiseAll: false))
    }
}
