import XCTest
@testable import HopCore

final class SoundInputSourceListTests: XCTestCase {
    func testPinnedSelectedOtherAndHiddenGroupsUseStableTypedIdentity() {
        let mic = SoundInputSourceID.device("same"), app = SoundInputSourceID.application("same")
        let unused = SoundInputSourceID.device("unused"), hidden = SoundInputSourceID.device("hidden")
        var list = SoundInputSourceListPreferences()
        list.setPinned(true, source: mic)
        XCTAssertTrue(list.setHidden(true, source: hidden, selected: false))
        let groups = list.groups([unused, app, mic, hidden, app], selected: [app])
        XCTAssertEqual(groups.primary, [mic, app])
        XCTAssertEqual(groups.other, [unused])
        XCTAssertEqual(groups.hidden, [hidden])
        XCTAssertEqual(list.groups([hidden], selected: [hidden]).primary, [hidden])
    }
    func testHideRestoreAndPinNeverEraseTheOtherSourcesChoices() throws {
        let source = SoundInputSourceID.device("fixture")
        var list = SoundInputSourceListPreferences()
        list.setPinned(true, source: source)
        XCTAssertFalse(list.setHidden(true, source: source, selected: true))
        XCTAssertTrue(list.pinned.contains(source))
        XCTAssertTrue(list.setHidden(true, source: source, selected: false))
        XCTAssertFalse(list.pinned.contains(source))
        let restored = SoundInputSourceListPreferences.load(try JSONEncoder().encode(list))
        XCTAssertEqual(restored.hidden, [source])
        list = restored
        XCTAssertTrue(list.setHidden(false, source: source, selected: false))
        XCTAssertEqual(list.groups([source], selected: []).other, [source])
        XCTAssertTrue(list.pinned.isEmpty)
        _ = list.setHidden(true, source: source, selected: false)
        list.setPinned(true, source: source)
        XCTAssertTrue(list.hidden.isEmpty)
    }
    func testInvalidPresentationDataDoesNotIntroduceNewSelections() {
        XCTAssertEqual(SoundInputSourceListPreferences.load(Data("invalid".utf8)), .init())
        XCTAssertEqual(SoundInputSourceListPreferences.load(Data("{\"schema\":99}".utf8)), .init())
    }
    func testIdentifierFallbackNeverOverwritesRememberedDisplayName() {
        let source = SoundInputSourceID.device("fixture-uid")
        var list = SoundInputSourceListPreferences()
        list.remember("Phone Microphone", source: source)
        list.remember(source.value, source: source)
        XCTAssertEqual(list.names[source], "Phone Microphone")
    }

}
