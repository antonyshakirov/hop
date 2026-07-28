import XCTest
@testable import HopCore

/// Which languages text recognition puts on the Vision request. Nothing chosen =
/// Vision detects the script itself, which measurement showed to be at least as
/// good as an explicit list on every image tried, and far better on CJK.
final class RecognitionPlanTests: XCTestCase {

    // The tags Vision reports on macOS 26 at .accurate, trimmed to what these
    // tests need — the real list is longer and versioned per OS.
    private let supported = ["en-US", "fr-FR", "de-DE", "zh-Hans", "zh-Hant",
                             "ko-KR", "ja-JP", "ru-RU", "uk-UA", "th-TH", "ar-SA"]

    func testNothingChosenMeansAutomaticDetection() {
        XCTAssertEqual(RecognitionPlan.languages(selected: [], supported: supported), [])
        XCTAssertTrue(RecognitionPlan.detectsAutomatically(selected: [], supported: supported))
    }

    func testAnExplicitChoiceIsUsedInOrderAndTurnsDetectionOff() {
        XCTAssertEqual(RecognitionPlan.languages(selected: ["ja-JP", "en-US"],
                                                 supported: supported),
                       ["ja-JP", "en-US"])
        XCTAssertFalse(RecognitionPlan.detectsAutomatically(selected: ["ja-JP"],
                                                            supported: supported))
    }

    func testTagsThisMachineDoesNotSupportAreDropped() {
        // An unsupported tag makes the WHOLE Vision request fail, so it must never
        // reach the request.
        XCTAssertEqual(RecognitionPlan.languages(selected: ["ja-JP", "xx-XX"],
                                                 supported: supported), ["ja-JP"])
    }

    func testAChoiceThisMachineCannotHonourFallsBackToDetection() {
        XCTAssertEqual(RecognitionPlan.languages(selected: ["xx-XX"], supported: supported), [])
        XCTAssertTrue(RecognitionPlan.detectsAutomatically(selected: ["xx-XX"],
                                                           supported: supported))
    }

    func testALanguageIsNeverRepeated() {
        XCTAssertEqual(RecognitionPlan.languages(selected: ["en-US", "en-US", "en"],
                                                 supported: supported), ["en-US"])
    }

    func testPrefixMatchingAcceptsABareLanguageCode() {
        XCTAssertEqual(RecognitionPlan.languages(selected: ["ja", "ru"], supported: supported),
                       ["ja-JP", "ru-RU"])
    }

    func testEverythingIsEmptyWhenVisionReportsNoModels() {
        XCTAssertEqual(RecognitionPlan.languages(selected: ["ja-JP"], supported: []), [])
        XCTAssertTrue(RecognitionPlan.detectsAutomatically(selected: ["ja-JP"], supported: []))
    }
}
