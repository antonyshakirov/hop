import XCTest
@testable import HopCore

final class SoundInputMixPreferencesTests: XCTestCase {
    func testFreshPresetIncludesOnlyTheSystemMicrophone() {
        let value = SoundInputMixPreferences.load(nil)
        XCTAssertTrue(value.system.active)
        XCTAssertEqual(value.resolvedInputs(defaultUID: "airpods", availableUIDs: ["airpods", "builtin"]).map(\.uid), ["airpods"])
        XCTAssertTrue(value.microphones.isEmpty); XCTAssertTrue(value.applications.isEmpty)
    }
    func testExplicitlyDisabledSystemAndAllSourceLevelsSurviveRoundTrip() throws {
        var value = SoundInputMixPreferences()
        value.system.active = false
        var microphone = SoundChannelSettings(); microphone.gain = 0.35; microphone.muted = true
        value.microphones["builtin"] = microphone
        value.applications["com.spotify.client"] = microphone
        let restored = SoundInputMixPreferences.load(try JSONEncoder().encode(value))
        XCTAssertEqual(restored, value)
        XCTAssertEqual(restored.resolvedInputs(defaultUID: "airpods", availableUIDs: ["builtin", "airpods"]).map(\.uid), ["builtin"])
    }
    func testSystemFollowsDefaultWhileNamedSourceKeepsItsUID() {
        var value = SoundInputMixPreferences()
        value.microphones["usb"] = .init()
        XCTAssertEqual(Set(value.resolvedInputs(defaultUID: "airpods", availableUIDs: ["airpods", "builtin", "usb"]).map(\.uid)), ["airpods", "usb"])
        XCTAssertEqual(Set(value.resolvedInputs(defaultUID: "builtin", availableUIDs: ["airpods", "builtin", "usb"]).map(\.uid)), ["builtin", "usb"])
    }
    func testDefaultAliasIsCapturedOnceAndExplicitChoiceIsRetained() {
        var value = SoundInputMixPreferences()
        value.system.gain = 0.7
        var explicit = SoundChannelSettings(); explicit.gain = 0.2
        value.microphones["airpods"] = explicit
        let first = value.resolvedInputs(defaultUID: "airpods", availableUIDs: ["airpods"])
        XCTAssertEqual(first.count, 1); XCTAssertEqual(first.first?.settings.gain, 0.7)
        value.system.active = false
        let second = value.resolvedInputs(defaultUID: "airpods", availableUIDs: ["airpods"])
        XCTAssertEqual(second.count, 1); XCTAssertEqual(second.first?.settings.gain, 0.2)
        XCTAssertEqual(value.microphones["airpods"], explicit)
    }
    func testMissingExplicitDeviceNeverFallsBackAndHopInputCannotFeedItself() {
        var value = SoundInputMixPreferences(); value.system.active = false
        value.microphones["missing"] = .init()
        XCTAssertTrue(value.resolvedInputs(defaultUID: "builtin", availableUIDs: ["builtin"]).isEmpty)
        value.system.active = true
        let own = "com.antonshakirov.hop.audio.dev.input"
        value.microphones[own] = .init()
        XCTAssertTrue(value.resolvedInputs(defaultUID: own, availableUIDs: [own, "builtin"]).isEmpty)
    }
    func testCorruptOrUnknownSavedPresetDoesNotReenableTheSystemSource() {
        for data in [Data("invalid".utf8), Data("{\"schema\":999}".utf8)] {
            let value = SoundInputMixPreferences.load(data)
            XCTAssertFalse(value.system.active)
            XCTAssertTrue(value.resolvedInputs(defaultUID: "builtin", availableUIDs: ["builtin"]).isEmpty)
        }
    }
}
