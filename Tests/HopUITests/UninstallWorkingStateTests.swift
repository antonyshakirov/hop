import XCTest
@testable import Hop

@MainActor
final class UninstallWorkingStateTests: XCTestCase {
    private final class Gate: @unchecked Sendable {
        let semaphore = DispatchSemaphore(value: 0)
        func open() { semaphore.signal() }
    }

    private func wait(_ done: () -> Bool) async {
        for _ in 0..<400 where !done() { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    func testClearingCachesShowsWorkingBeforeTheDiskFinishes() async {
        let gate = Gate()
        let controller = UninstallController()
        controller.trashWork = { paths in
            gate.semaphore.wait()
            var outcome = UninstallController.TrashOutcome()
            outcome.trashed = paths.count
            return outcome
        }
        controller.cacheOwners = [.init(identifier: "x.y", name: "Y", appPath: nil,
                                        paths: ["/tmp/none-a"], bytes: 1, ticked: true)]
        controller.clearTickedCaches()
        XCTAssertEqual(controller.state, .working)
        XCTAssertNil(controller.report)
        gate.open()
        await wait { controller.state == .done }
        XCTAssertEqual(controller.state, .done)
        XCTAssertEqual(controller.report?.trashed, 1)
        XCTAssertTrue(controller.cacheOwners.isEmpty)
    }

    func testASecondClickWhileWorkingDoesNotStartASecondRun() async {
        let gate = Gate()
        let calls = Counter()
        let controller = UninstallController()
        controller.trashWork = { _ in calls.bump(); gate.semaphore.wait(); return .init() }
        controller.leftovers = [.init(identifier: "a.b", name: "B", appPath: nil,
                                      paths: ["/tmp/none-b"], bytes: 1, ticked: true)]
        controller.removeTickedLeftovers()
        controller.removeTickedLeftovers()
        gate.open()
        await wait { controller.state == .done }
        XCTAssertEqual(calls.count, 1)
    }

    func testEmptyingTheTrashIsVisibleAtOnceAndEndsMeasured() async {
        let gate = Gate()
        let controller = UninstallController()
        controller.emptyTrashWork = { gate.semaphore.wait(); return (bytes: 0, items: 0) }
        controller.emptyTrash()
        XCTAssertTrue(controller.emptyingTrash)
        gate.open()
        await wait { !controller.emptyingTrash }
        XCTAssertFalse(controller.emptyingTrash)
        XCTAssertEqual(controller.trashItems, 0)
    }

    func testRemoveShowsWorkingBeforeTheDiskFinishes() async throws {
        // the staged target is Krita; never ask a real one to quit
        try XCTSkipUnless(NSRunningApplication.runningApplications(withBundleIdentifier: "org.krita.krita").isEmpty)
        let gate = Gate()
        let controller = UninstallController()
        controller.stageDemo(.uninstall)
        controller.removeWork = { _ in gate.semaphore.wait(); return .init() }
        let running = Task { await controller.removeTicked() }
        await Task.yield()
        XCTAssertEqual(controller.state, .working)
        gate.open()
        await running.value
        XCTAssertEqual(controller.state, .done)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
