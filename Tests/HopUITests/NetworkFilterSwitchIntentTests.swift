import XCTest
@testable import Hop

@MainActor
final class NetworkFilterSwitchIntentTests: XCTestCase {
    private struct Refused: Error {}

    private func make(_ apply: @escaping (Bool) async throws -> Void) -> NetworkFilterController {
        let controller = NetworkFilterController()
        controller.stageForSnapshot("on")
        controller.applyConfiguration = apply
        return controller
    }

    func testSwitchShowsOffBeforeTheSystemReplies() async {
        var reply: CheckedContinuation<Void, Error>?
        let saved = Snapshot.active; Snapshot.active = true
        defer { Snapshot.active = saved }
        let network = make { _ in try await withCheckedThrowingContinuation { reply = $0 } }
        XCTAssertTrue(network.shownOn)
        network.switchOff()
        XCTAssertFalse(network.shownOn)
        XCTAssertEqual(network.state, .on)
        for _ in 0..<100 where reply == nil { await Task.yield() }
        reply?.resume()
        for _ in 0..<100 where network.state != .off { await Task.yield() }
        XCTAssertEqual(network.state, .off)
        XCTAssertFalse(network.shownOn)
        XCTAssertFalse(network.switchingOff)
    }

    func testRefusedSwitchOffEndsInTheFailureCard() async {
        let saved = Snapshot.active; Snapshot.active = true
        defer { Snapshot.active = saved }
        let network = make { _ in throw Refused() }
        network.switchOff()
        XCTAssertFalse(network.shownOn)
        for _ in 0..<100 where network.switchingOff { await Task.yield() }
        XCTAssertFalse(network.switchingOff)
        if case .failed = network.state {} else { XCTFail("expected failed, got \(network.state)") }
    }
}
