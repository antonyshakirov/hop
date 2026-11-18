import XCTest
@testable import Hop

@MainActor
final class KeyboardLockIntentTests: XCTestCase {
    func testChipLightsOnClickWhileTheProbeRuns() {
        let lock = KeyboardLockController()
        lock.trusted = { true }
        lock.installTapHook = { true }
        var finish: ((Bool) -> Void)?
        lock.proofHook = { finish = $0 }
        lock.lock(seconds: 300)
        XCTAssertEqual(lock.locking, 300)
        XCTAssertFalse(lock.isLocked)
        XCTAssertNotNil(finish)
        // a second click while proving changes nothing
        var secondAnswer: Bool?
        lock.lock(seconds: 900) { secondAnswer = $0 }
        XCTAssertEqual(secondAnswer, false)
        XCTAssertEqual(lock.locking, 300)
        XCTAssertEqual(lock.duration, 300)
        UserDefaults.standard.removeObject(forKey: KeyboardLockController.durationKey)
    }
}
