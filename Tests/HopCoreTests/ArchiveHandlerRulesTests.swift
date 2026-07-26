import XCTest
@testable import HopCore

final class ArchiveHandlerRulesTests: XCTestCase {
    private let hop = "com.antonshakirov.minimo"

    func testOnlyRarIsClaimable() {
        XCTAssertEqual(
            ArchiveHandlerRules.claimableContentTypes,
            ["com.rarlab.rar-archive"])
    }

    func testAppleHandlerIsNeverReplaced() {
        XCTAssertFalse(
            ArchiveHandlerRules.shouldClaim(
                currentHandler: "com.apple.archiveutility",
                hopBundleID: hop))
    }

    func testUnclaimedAndThirdPartyRarCanBeClaimed() {
        XCTAssertTrue(
            ArchiveHandlerRules.shouldClaim(
                currentHandler: nil,
                hopBundleID: hop))
        XCTAssertTrue(
            ArchiveHandlerRules.shouldClaim(
                currentHandler: "com.example.archiver",
                hopBundleID: hop))
    }

    func testHopHeldRarDoesNotNeedToBeClaimedAgain() {
        XCTAssertFalse(
            ArchiveHandlerRules.shouldClaim(
                currentHandler: hop.uppercased(),
                hopBundleID: hop))
    }

    func testLegacySystemTypeOwnershipIsDetected() {
        XCTAssertTrue(
            ArchiveHandlerRules.holdsUnexpectedType(
                contentType: "public.zip-archive",
                currentHandler: hop,
                hopBundleID: hop))
        XCTAssertFalse(
            ArchiveHandlerRules.holdsUnexpectedType(
                contentType: "com.rarlab.rar-archive",
                currentHandler: hop,
                hopBundleID: hop))
        XCTAssertFalse(
            ArchiveHandlerRules.holdsUnexpectedType(
                contentType: "public.zip-archive",
                currentHandler: "com.apple.archiveutility",
                hopBundleID: hop))
    }
}
