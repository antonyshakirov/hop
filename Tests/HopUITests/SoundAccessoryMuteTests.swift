import AVFoundation
import HopAudioEngine
import XCTest
@testable import Hop

final class SoundAccessoryMuteTests: XCTestCase {
    func testGestureAppliesBeforeAcknowledgementAndDeduplicatesState() {
        let gate = SoundAccessoryMuteGate()
        var actual = false, applications = 0, states: [Bool] = []
        gate.bind(UUID(), muted: false, apply: { actual = $0; applications += 1; return true }, changed: { states.append($0) })
        XCTAssertTrue(gate.request(true))
        XCTAssertTrue(actual); XCTAssertTrue(gate.muted)
        XCTAssertEqual(states, [true]); XCTAssertEqual(applications, 1)
        XCTAssertTrue(gate.request(true)); XCTAssertEqual(applications, 1)
        XCTAssertTrue(gate.request(false)); XCTAssertFalse(actual)
        XCTAssertEqual(states, [true, false])
    }
    func testFailureCannotConfirmMuteAndIdleGestureNeverStartsCapture() {
        let gate = SoundAccessoryMuteGate(); var changes = 0
        XCTAssertTrue(gate.request(true)); XCTAssertFalse(gate.muted)
        gate.bind(UUID(), muted: false, apply: { _ in false }, changed: { _ in changes += 1 })
        XCTAssertFalse(gate.request(true)); XCTAssertFalse(gate.muted); XCTAssertEqual(changes, 0)
    }
    func testRetiredTargetCannotUnbindANewerCapture() {
        let gate = SoundAccessoryMuteGate(), old = UUID(), new = UUID()
        var a = 0, b = 0
        gate.bind(old, muted: false, apply: { _ in a += 1; return true }, changed: { _ in })
        gate.bind(new, muted: false, apply: { _ in b += 1; return true }, changed: { _ in })
        gate.unbind(old); XCTAssertTrue(gate.request(true)); XCTAssertEqual(a, 0); XCTAssertEqual(b, 1)
        gate.unbind(new); XCTAssertTrue(gate.request(false)); XCTAssertEqual(b, 1)
    }
    func testRelayAcceptsOnlyMatchingCaptureAndRequestAcknowledgements() throws {
        var relay: SoundAccessoryMuteRelay!
        relay = SoundAccessoryMuteRelay { data in
            let request = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            var reply = request; reply["muteApplied"] = true
            reply["captureToken"] = "retired"
            relay.consume(try JSONSerialization.data(withJSONObject: reply) + Data([10]))
            reply["captureToken"] = request["captureToken"]
            let line = try JSONSerialization.data(withJSONObject: reply) + Data([10])
            relay.consume(line.prefix(5)); relay.consume(line.dropFirst(5))
        }
        relay.select("current")
        XCTAssertFalse(relay.request(true, token: "retired", timeout: 0.01))
        XCTAssertTrue(relay.request(true, token: "current", timeout: 0.01))
        relay.select(nil)
        XCTAssertFalse(relay.request(false, token: "current", timeout: 0.01))
    }
    func testRelayTimeoutAndCloseCannotConfirmAnUnacknowledgedMute() {
        let relay = SoundAccessoryMuteRelay { _ in }
        relay.select("current")
        XCTAssertFalse(relay.request(true, token: "current", timeout: 0.001))
        var closing: SoundAccessoryMuteRelay!
        closing = SoundAccessoryMuteRelay { _ in closing.select(nil) }
        closing.select("current")
        XCTAssertFalse(closing.request(true, token: "current", timeout: 0.01))
    }
    func testConfirmingWorkerStateDoesNotSendAnotherCommand() {
        let gate = SoundAccessoryMuteGate(), token = UUID(); var applications = 0
        gate.bind(token, muted: false, apply: { _ in applications += 1; return true }, changed: { _ in })
        gate.confirm(token, muted: true)
        XCTAssertTrue(gate.muted); XCTAssertTrue(gate.request(true)); XCTAssertEqual(applications, 0)
        gate.confirm(UUID(), muted: false); XCTAssertTrue(gate.muted)
    }

    func testUnbindWaitsForInFlightMuteBeforeTheCaptureCanBeRebuilt() {
        let gate = SoundAccessoryMuteGate(), token = UUID()
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let retired = DispatchSemaphore(value: 0)
        gate.bind(token, muted: false, apply: { _ in
            entered.signal(); return release.wait(timeout: .now() + 2) == .success
        }, changed: { _ in })
        DispatchQueue.global().async { _ = gate.request(true) }
        XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)
        DispatchQueue.global().async { gate.unbind(token); retired.signal() }
        XCTAssertEqual(retired.wait(timeout: .now() + 0.01), .timedOut)
        release.signal()
        XCTAssertEqual(retired.wait(timeout: .now() + 1), .success)
        XCTAssertFalse(gate.muted)
    }

}
