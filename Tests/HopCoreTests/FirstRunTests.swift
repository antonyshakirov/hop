import XCTest
@testable import HopCore

final class FirstRunTests: XCTestCase {
    func testAnEmptyDomainIsAFreshInstall() {
        XCTAssertTrue(FirstRun.isFresh(domain: [:]))
    }

    func testKeysThatAreNotOursDoNotCount() {
        XCTAssertTrue(FirstRun.isFresh(domain: [
            "NSWindow Frame SUStatusFrame": "0 0 400 200",
            "AppleLanguages": ["en"],
            "NSNavLastRootDirectory": "~/Downloads",
        ]))
    }

    func testAStoredArrangementMeansHopHasRunBefore() {
        XCTAssertFalse(FirstRun.isFresh(domain: ["panelTabs": "{}"]))
    }

    func testAReleaseFlagMeansHopHasRunBefore() {
        XCTAssertFalse(FirstRun.isFresh(domain: ["newsSeen.1.9": true]))
        XCTAssertFalse(FirstRun.isFresh(domain: ["featureSeen.torrent": true]))
        XCTAssertFalse(FirstRun.isFresh(domain: ["permissionsReset.1.10.0": true]))
    }

    func testAHalfFinishedWizardIsNotFresh() {
        XCTAssertFalse(FirstRun.isFresh(domain: ["onboardingStep": 3]))
    }

    func testEveryMarkIsRecognised() {
        for mark in FirstRun.marks {
            XCTAssertFalse(FirstRun.isFresh(domain: [mark: true]), mark)
        }
    }

    func testANewMacGetsTheWizard() {
        XCTAssertTrue(FirstRun.needsWizard(domain: [:]))
    }

    func testAnUpdateSkipsTheWizard() {
        XCTAssertFalse(FirstRun.needsWizard(domain: ["panelTabs": "{}", "newsSeen.1.9": true]))
    }

    func testAWizardLeftHalfwayReopens() {
        XCTAssertTrue(FirstRun.needsWizard(domain: [
            "panelTabs": "{}", "onboardingSeededAllOn": true, "onboardingStep": 6,
        ]))
    }

    func testAWizardQuitOnItsFirstScreenReopens() {
        XCTAssertTrue(FirstRun.needsWizard(domain: [
            "panelTabs": "{}", "onboardingSeededAllOn": true,
        ]))
    }

    func testAFinishedWizardStaysFinished() {
        XCTAssertFalse(FirstRun.needsWizard(domain: [
            "onboardingDone": true, "onboardingSeededAllOn": true, "onboardingStep": 6,
        ]))
    }
}
