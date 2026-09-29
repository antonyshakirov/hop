import XCTest
@testable import HopCore

final class RecognitionWarmUpTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    func testDueAfterAnUpdateChangesTheExecutable() {
        let old = RecognitionWarmUp.key(size: 100, modified: date)
        let new = RecognitionWarmUp.key(size: 100, modified: date.addingTimeInterval(60))
        XCTAssertNotEqual(old, new)
        XCTAssertTrue(RecognitionWarmUp.isDue(warmedFor: old, current: new, moduleOn: true))
        XCTAssertTrue(RecognitionWarmUp.isDue(warmedFor: nil, current: new, moduleOn: true))
    }

    func testNotDueTwiceForTheSameExecutable() {
        let key = RecognitionWarmUp.key(size: 100, modified: date)
        XCTAssertFalse(RecognitionWarmUp.isDue(warmedFor: key, current: key, moduleOn: true))
    }

    func testNotDueWhileTheModuleIsOff() {
        let key = RecognitionWarmUp.key(size: 100, modified: date)
        XCTAssertFalse(RecognitionWarmUp.isDue(warmedFor: nil, current: key, moduleOn: false))
        XCTAssertFalse(RecognitionWarmUp.isDue(warmedFor: nil, current: nil, moduleOn: true))
    }

    func testHelperSetsCoverEitherScriptLeadingTheFirstPass() {
        let supported = TextScript.allCases.map(\.recognitionTag)
        XCTAssertEqual(RecognitionWarmUp.helperTagSets(interface: .cyrillic, supported: supported),
                       [["ru-RU", "en-US"], ["en-US", "ru-RU"]])
        XCTAssertEqual(RecognitionWarmUp.helperTagSets(interface: .latin, supported: supported),
                       [["en-US"]])
        XCTAssertEqual(RecognitionWarmUp.helperTagSets(interface: .cyrillic, supported: ["en-US"]),
                       [["en-US"]])
    }

    func testBeforeTheWarmUpTheFirstPassNamesTheReadersLanguageAndEnglish() {
        let supported = TextScript.allCases.map(\.recognitionTag)
        XCTAssertEqual(RecognitionWarmUp.quickLanguages(interface: .cyrillic, supported: supported),
                       ["ru-RU", "en-US"])
        XCTAssertEqual(RecognitionWarmUp.quickLanguages(interface: .latin, supported: supported), ["en-US"])
        XCTAssertEqual(RecognitionWarmUp.quickLanguages(interface: .cjk, supported: supported),
                       ["ja-JP", "en-US"])
    }

    func testBeforeTheWarmUpTheSecondPassSkipsTheSlowReader() {
        XCTAssertEqual(RecognitionWarmUp.quickHelpers(["ru-RU", "ja-JP"], interface: .cyrillic), ["ru-RU"])
        XCTAssertEqual(RecognitionWarmUp.quickHelpers(["ja-JP", "en-US"], interface: .cjk), ["ja-JP", "en-US"])
    }
}
