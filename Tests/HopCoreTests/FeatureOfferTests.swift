import XCTest
@testable import HopCore

final class FeatureOfferTests: XCTestCase {
    func testAModuleAlreadyInThePanelIsNotOffered() {
        XCTAssertEqual(FeatureOffer.remaining(["vpn", "apps"], active: ["vpn"]), ["apps"])
    }

    /// The whole point: a card that offers what is already on reads as if the
    /// app had forgotten the user.
    func testNothingLeftMeansNoCard() {
        XCTAssertFalse(FeatureOffer.worthShowing(["vpn", "apps"], active: ["vpn", "apps"]))
        XCTAssertTrue(FeatureOffer.worthShowing(["vpn", "apps"], active: ["vpn"]))
    }

    func testAnEmptyPanelIsOfferedEverything() {
        XCTAssertEqual(FeatureOffer.remaining(["vpn", "apps"], active: []), ["vpn", "apps"])
        XCTAssertTrue(FeatureOffer.worthShowing(["uninstall"], active: []))
    }

    func testTheOrderOfTheCardIsKept() {
        XCTAssertEqual(FeatureOffer.remaining(["a", "b", "c"], active: ["b"]), ["a", "c"])
    }
}
