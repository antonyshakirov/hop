import XCTest
@testable import Hop

@MainActor
final class PasteActivationTests: XCTestCase {
    func testPasteWaitsForTheCapturedAppAndRunsOnce() {
        let gate = PasteActivationGate(targetPID: 4001)
        XCTAssertFalse(gate.consume(activatedPID: 4002))
        XCTAssertTrue(gate.pending)
        XCTAssertTrue(gate.consume(activatedPID: 4001))
        XCTAssertFalse(gate.consume(activatedPID: 4001))
    }

    func testCancelledPasteDoesNotRunAfterActivation() {
        let gate = PasteActivationGate(targetPID: 4001)
        gate.cancel()
        XCTAssertFalse(gate.consume(activatedPID: 4001))
    }
}
