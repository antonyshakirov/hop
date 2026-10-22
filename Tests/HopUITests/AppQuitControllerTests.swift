import AppKit
import Foundation
import HopCore
import XCTest
@testable import Hop

@MainActor
final class AppQuitControllerTests: XCTestCase {
    private final class Backend: AppQuitBackend {
        var applications: [AppQuitApplication] = []
        var requests: [AppQuitApplication] = []
        var accepts = true
        var changed: (@MainActor () -> Void)?
        var onRequest: ((AppQuitApplication) -> Void)?
        func requestQuit(_ application: AppQuitApplication) -> Bool {
            requests.append(application)
            onRequest?(application)
            return accepts
        }
        func observeChanges(_ changed: @escaping @MainActor () -> Void) { self.changed = changed }
        func icon(for application: AppQuitApplication) -> NSImage? { nil }
    }

    private func app(_ pid: Int32, _ bundle: String? = "test.app", launched: TimeInterval = 1) -> AppQuitApplication {
        AppQuitApplication(processIdentifier: pid, bundleIdentifier: bundle, name: "App \(pid)",
                           launchDate: Date(timeIntervalSince1970: launched))
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "AppQuitControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    private func controller(_ backend: Backend, defaults: UserDefaults, preview: Bool = false) -> AppQuitController {
        AppQuitController(backend: backend, defaults: defaults, ownProcessIdentifier: 99,
                          ownBundleIdentifier: "test.hop", preview: preview)
    }

    func testConstructionRefreshAndNotificationsNeverQuitApplications() {
        withDefaults { defaults in
            let backend = Backend(); backend.applications = [app(1)]
            let controller = controller(backend, defaults: defaults)
            XCTAssertEqual(controller.applications.count, 1)
            controller.refresh()
            backend.applications.append(app(2, "test.second")); backend.changed?()
            XCTAssertEqual(controller.applications.count, 2)
            XCTAssertTrue(backend.requests.isEmpty)
        }
    }

    func testPinsProtectIndividualAndBatchQuitAndPersistAcrossRelaunch() {
        withDefaults { defaults in
            let backend = Backend(); let kept = app(1, "test.kept"); let other = app(2, "test.other")
            backend.applications = [kept, other]
            let controller = controller(backend, defaults: defaults)
            controller.setPinned(true, for: kept.id)
            controller.quit(kept.id); controller.quitAllUnpinned()
            XCTAssertEqual(backend.requests, [other])
            XCTAssertEqual(controller.unpinnedCount, 1)
            backend.applications = [app(3, "test.kept", launched: 2)]
            let reopened = self.controller(backend, defaults: defaults)
            XCTAssertTrue(reopened.isPinned(backend.applications[0]))
            reopened.quitAllUnpinned()
            XCTAssertEqual(backend.requests, [other])
            reopened.setPinned(false, for: backend.applications[0].id)
            reopened.quitAllUnpinned()
            XCTAssertEqual(backend.requests.last, backend.applications[0])
            XCTAssertEqual(defaults.stringArray(forKey: AppQuitController.pinnedDefaultsKey), [])
        }
    }

    func testStaleRowNeverQuitsReplacementWithSameProcessIdentifier() {
        withDefaults { defaults in
            let backend = Backend(); let old = app(1)
            backend.applications = [old]
            let controller = controller(backend, defaults: defaults)
            backend.applications = [app(1, launched: 2)]
            controller.quit(old.id)
            XCTAssertTrue(backend.requests.isEmpty)
            XCTAssertEqual(controller.applications, backend.applications)
        }
    }

    func testBatchRechecksApplicationsBeforeEachRequest() {
        withDefaults { defaults in
            let backend = Backend(); let first = app(1, "test.first"); let second = app(2, "test.second")
            backend.applications = [first, second]
            let controller = controller(backend, defaults: defaults)
            backend.onRequest = { _ in backend.applications.removeAll { $0.id == second.id } }
            controller.quitAllUnpinned()
            XCTAssertEqual(backend.requests, [first])
        }
    }

    func testAcceptedRequestDoesNotPretendApplicationClosedAndCanBeRetried() {
        withDefaults { defaults in
            let backend = Backend(); let application = app(1)
            backend.applications = [application]
            let controller = controller(backend, defaults: defaults)
            controller.quit(application.id)
            XCTAssertEqual(controller.requestStates[application.id], .requested)
            XCTAssertEqual(controller.applications, [application])
            backend.changed?()
            XCTAssertEqual(controller.applications, [application])
            controller.quit(application.id)
            XCTAssertEqual(backend.requests.count, 2)
            backend.applications = []; backend.changed?()
            XCTAssertTrue(controller.applications.isEmpty)
            XCTAssertTrue(controller.requestStates.isEmpty)
        }
    }

    func testRefusedRequestStaysVisibleAndReportsRefusal() {
        withDefaults { defaults in
            let backend = Backend(); backend.accepts = false
            let application = app(1); backend.applications = [application]
            let controller = controller(backend, defaults: defaults)
            controller.quit(application.id)
            XCTAssertEqual(controller.requestStates[application.id], .refused)
            XCTAssertEqual(controller.applications, [application])
        }
    }

    func testImmediateExitDuringRequestDoesNotLeaveStaleStatus() {
        withDefaults { defaults in
            let backend = Backend(); let application = app(1); backend.applications = [application]
            let controller = controller(backend, defaults: defaults)
            backend.onRequest = { _ in backend.applications = []; backend.changed?() }
            controller.quit(application.id)
            XCTAssertTrue(controller.applications.isEmpty)
            XCTAssertTrue(controller.requestStates.isEmpty)
        }
    }

    func testMissingBundleIdentifierCannotBePinned() {
        withDefaults { defaults in
            let backend = Backend(); let application = app(1, nil); backend.applications = [application]
            let controller = controller(backend, defaults: defaults)
            controller.setPinned(true, for: application.id)
            XCTAssertFalse(controller.isPinned(application))
            XCTAssertNil(defaults.object(forKey: AppQuitController.pinnedDefaultsKey))
        }
    }

    func testPreviewNeverPersistsPinsOrQuits() {
        withDefaults { defaults in
            let backend = Backend(); let application = app(1); backend.applications = [application]
            let controller = controller(backend, defaults: defaults, preview: true)
            controller.setPinned(true, for: application.id)
            controller.quit(application.id); controller.quitAllUnpinned()
            XCTAssertTrue(backend.requests.isEmpty)
            XCTAssertNil(defaults.object(forKey: AppQuitController.pinnedDefaultsKey))
        }
    }
}
