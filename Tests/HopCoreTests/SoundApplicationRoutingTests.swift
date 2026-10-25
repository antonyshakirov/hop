import XCTest
@testable import HopCore

final class SoundApplicationRoutingTests: XCTestCase {
    func testOwnVirtualDevicesCannotFeedListeningBackIntoHop() {
        let uid = "com.antonshakirov.hop.audio.mix"
        XCTAssertNil(SoundAppOutput.resolve(selectedUID: uid, systemUID: "speakers", available: [uid, "speakers"]))
        XCTAssertNil(SoundAppOutput.resolve(selectedUID: nil, systemUID: uid, available: [uid]))
    }
    func testExplicitMissingDestinationNeverFallsBackToSystem() {
        XCTAssertNil(SoundAppOutput.resolve(selectedUID: "headphones", systemUID: "speakers", available: ["speakers"]))
        XCTAssertEqual(SoundAppOutput.resolve(selectedUID: "headphones", systemUID: "speakers", available: ["speakers", "headphones"]), "headphones")
        XCTAssertEqual(SoundAppOutput.resolve(selectedUID: nil, systemUID: "speakers", available: ["speakers"]), "speakers")
        XCTAssertNil(SoundAppOutput.resolve(selectedUID: nil, systemUID: "removed", available: ["speakers"]))
    }
    func testSystemChangeOnlyChangesFollowingApplications() {
        for system in ["speakers", "usb"] {
            XCTAssertEqual(SoundAppOutput.resolve(selectedUID: "headphones", systemUID: system, available: ["speakers", "usb", "headphones"]), "headphones")
            XCTAssertEqual(SoundAppOutput.resolve(selectedUID: nil, systemUID: system, available: ["speakers", "usb", "headphones"]), system)
        }
    }
    func testPreferencesRoundTripByIdentityAndDoNotChangeAudioSettings() throws {
        var preferences = SoundAppPreference(name: "Browser")
        preferences.pinned = true; preferences.order = 3
        preferences.outputUID = "usb.uid"; preferences.outputName = "USB"
        let data = try JSONEncoder().encode(["bundle.browser": preferences])
        let restored = try JSONDecoder().decode([String: SoundAppPreference].self, from: data)
        XCTAssertEqual(restored["bundle.browser"], preferences)
        XCTAssertNil(restored["another.bundle"])
        let settings = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SoundChannelSettings())) as! [String: Any]
        XCTAssertNil(settings["outputUID"], "Listening routes must never travel in microphone/HopMix settings")
    }
    func testPartialPreferenceDecodesDefaults() throws {
        let value = try JSONDecoder().decode(SoundAppPreference.self, from: Data(#"{"name":"Browser"}"#.utf8))
        XCTAssertFalse(value.pinned); XCTAssertNil(value.order); XCTAssertNil(value.outputUID)
    }
    func testPinnedFirstManualOrderStableAndEqualNamesRemainDistinct() {
        let ids = ["z", "b", "a", "new"]
        let names = ["a": "Same", "b": "Same", "z": "Zoom", "new": "A new app"]
        var preferences = ["a": SoundAppPreference(name: "Same"), "b": SoundAppPreference(name: "Same"), "z": SoundAppPreference(name: "Zoom")]
        preferences["z"]!.pinned = true
        preferences["b"]!.order = 0; preferences["a"]!.order = 1
        XCTAssertEqual(SoundApplicationList.ordered(ids, names: names, preferences: preferences), ["z", "b", "a", "new"])
        XCTAssertEqual(SoundApplicationList.ordered(["b", "a"], names: names, preferences: [:]), ["a", "b"])
    }
    func testMoveWithinGroupRetainsRouteAndPinning() {
        let names = ["a": "A", "b": "B", "c": "C"]
        var preferences = ["a": SoundAppPreference(name: "A"), "b": SoundAppPreference(name: "B"), "c": SoundAppPreference(name: "C")]
        preferences["a"]!.pinned = true; preferences["b"]!.pinned = true
        preferences["a"]!.outputUID = "headphones"
        let moved = SoundApplicationList.moving("a", by: 1, ids: ["a", "b", "c"], names: names, preferences: preferences)
        XCTAssertEqual(SoundApplicationList.ordered(["a", "b", "c"], names: names, preferences: moved), ["b", "a", "c"])
        XCTAssertEqual(moved["a"]?.outputUID, "headphones")
        XCTAssertTrue(moved["a"]!.pinned)
        let boundary = SoundApplicationList.moving("a", by: 1, ids: ["a", "b", "c"], names: names, preferences: moved)
        XCTAssertEqual(boundary, moved, "A row must not cross the pin boundary through Move")
    }
}
