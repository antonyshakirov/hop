import Foundation
import XCTest
@testable import Hop

final class SoundOutputEngineLifetimeTests: XCTestCase {
    private final class Resource {
        let dispose: () -> Void
        init(dispose: @escaping () -> Void) { self.dispose = dispose }
        deinit { dispose() }
    }

    func testBlockedDestructionDoesNotBlockMainQueue() async {
        let began = expectation(description: "destruction began off main")
        let finished = expectation(description: "destruction finished")
        let mainResponsive = expectation(description: "main remains responsive")
        let unblock = DispatchSemaphore(value: 0)
        await MainActor.run {
            var owner: SoundOutputEngineLifetime<Resource>? = .init(make: {
                Resource {
                    XCTAssertFalse(Thread.isMainThread)
                    began.fulfill()
                    _ = unblock.wait(timeout: .now() + 3)
                    finished.fulfill()
                }
            })
            owner?.withResource { _ in }
            owner = nil
            DispatchQueue.main.async { mainResponsive.fulfill() }
        }
        await fulfillment(of: [began, mainResponsive], timeout: 2)
        unblock.signal()
        await fulfillment(of: [finished], timeout: 2)
    }

    func testBorrowKeepsOwnerAliveUntilThrowingClosureFinishes() async {
        let disposed = expectation(description: "disposed after borrow")
        let lock = NSLock()
        var borrowing = false
        enum Failure: Error { case expected }
        var owner: SoundOutputEngineLifetime<Resource>? = .init(make: {
            Resource {
                lock.withLock { XCTAssertFalse(borrowing) }
                XCTAssertFalse(Thread.isMainThread)
                disposed.fulfill()
            }
        })
        XCTAssertThrowsError(try owner?.withResource { _ in
            lock.withLock { borrowing = true }
            owner = nil
            Thread.sleep(forTimeInterval: 0.03)
            lock.withLock { borrowing = false }
            throw Failure.expected
        })
        await fulfillment(of: [disposed], timeout: 2)
    }

    @MainActor
    func testFailedInitializationAlsoDestroysResourceOffMain() async {
        let disposed = expectation(description: "failed initialization disposed")
        enum Failure: Error { case expected }
        func fail() throws {
            let owner = SoundOutputEngineLifetime(make: {
                Resource { XCTAssertFalse(Thread.isMainThread); disposed.fulfill() }
            })
            try owner.withResource { _ in throw Failure.expected }
        }
        XCTAssertThrowsError(try fail())
        await fulfillment(of: [disposed], timeout: 2)
    }
}
