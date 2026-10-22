import Foundation
import XCTest
@testable import HopCore

final class AppQuitPolicyTests: XCTestCase {
    private func app(_ pid: Int32, _ bundle: String?, name: String = "App", regular: Bool = true,
                     terminated: Bool = false, launched: TimeInterval = 1) -> AppQuitApplication {
        AppQuitApplication(processIdentifier: pid, bundleIdentifier: bundle, name: name,
                           launchDate: Date(timeIntervalSince1970: launched),
                           isRegular: regular, isTerminated: terminated)
    }

    func testOnlyRunningRegularApplicationsAreListed() {
        let safari = app(1, "com.apple.Safari", name: "Safari")
        let hidden = app(2, "test.hidden", regular: false)
        let terminated = app(3, "test.terminated", terminated: true)
        XCTAssertEqual(AppQuitPolicy.visibleApplications([hidden, safari, terminated], ownProcessIdentifier: 99), [safari])
    }

    func testFinderCurrentProcessAndEveryKnownHopFamilyAreExcluded() {
        let protected = [app(1, "com.apple.finder"), app(99, nil), app(2, "com.antonshakirov.minimo"),
                         app(3, "com.antonshakirov.minimo.dev"), app(4, "com.antonshakirov.hop"),
                         app(5, "COM.ANTONSHAKIROV.HOP.experimental"), app(6, "test.custom-hop")]
        XCTAssertTrue(AppQuitPolicy.visibleApplications(protected, ownProcessIdentifier: 99,
                                                       ownBundleIdentifier: "test.custom-hop").isEmpty)
    }

    func testDuplicateWorkspaceEntriesHaveOneStableRow() {
        let app = app(1, "test.app")
        XCTAssertEqual(AppQuitPolicy.visibleApplications([app, app], ownProcessIdentifier: 99), [app])
    }

    func testPinnedBundleProtectsEveryInstanceAfterRelaunch() {
        let first = app(1, "test.kept", launched: 1)
        let relaunched = app(2, "test.kept", launched: 2)
        let other = app(3, "test.other")
        XCTAssertEqual(AppQuitPolicy.quitCandidates([first, other, relaunched], pinnedBundleIdentifiers: ["TEST.KEPT"],
                                                    ownProcessIdentifier: 99), [other])
    }

    func testIdentityDistinguishesReusedProcessIdentifier() {
        XCTAssertNotEqual(app(1, "test.app", launched: 1).id, app(1, "test.app", launched: 2).id)
        XCTAssertNotEqual(app(1, "test.app").id, app(1, "test.other").id)
    }

    func testMissingBundleIdentifierCannotBecomePersistentPin() {
        XCTAssertNil(app(1, nil).pinIdentifier)
        XCTAssertNil(app(2, " \n").pinIdentifier)
        XCTAssertEqual(app(3, " TEST.App ").pinIdentifier, "test.app")
    }
}
