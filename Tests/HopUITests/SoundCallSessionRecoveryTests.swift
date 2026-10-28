import Foundation
import XCTest
@testable import Hop

/// Real subprocess pipes exercise the session, but the producer has no audio I/O,
/// permission request or virtual CoreAudio device. It only exchanges fixture JSON.
@available(macOS 14.2, *)
@MainActor
final class SoundCallSessionRecoveryTests: XCTestCase {
    @MainActor
    private final class Fixture {
        var producers: [Process] = []
        var published = 0
        var retired = 0
        var retirementAttempts = 0
        var retirementFailures = 0
        var publishFailureAt: Int?
        var scripts: [String]
        init(_ scripts: [String]) { self.scripts = scripts }
        lazy var session = NativeSoundCallSession(makeProducer: { [unowned self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", scripts.removeFirst()]
            producers.append(process)
            return process
        }, publishInput: { [unowned self] _ in
            published += 1
            if published == publishFailureAt { throw NSError(domain: "fixture-publication", code: 1) }
            return { [unowned self] in
                retirementAttempts += 1
                if retirementFailures > 0 { retirementFailures -= 1; throw SoundFailure.system(-50) }
                retired += 1
            }
        }, installAccessory: {})
        func cleanup() { session.shutdown() }
    }
    private let good = """
        printf '{"ready":true}\n'
        while IFS= read -r command; do
            request=${command#*requestID}
            request=${request#*:}
            request=${request%%[!0-9]*}
            printf '{"applied":%s,"captureCount":0}\n' "$request"
        done
        """
    private func waitFor(_ predicate: () -> Bool, timeout: TimeInterval = 2,
                         file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(predicate(), file: file, line: line)
    }

    func testNormalStopWithdrawsInputAndExplicitRestartPublishesAgain() {
        let f = Fixture([good]); defer { f.cleanup() }
        var started = false
        f.session.start(.init(input: nil, apps: [])) { if case .success = $0 { started = true } }
        waitFor { started }
        var stopped = false
        f.session.stop { if case .success = $0 { stopped = true } }
        waitFor { stopped }
        XCTAssertEqual(f.retired, 1, "Stop completion must not leave a selectable silent input")
        var restarted = false
        f.session.start(.init(input: nil, apps: [])) { if case .success = $0 { restarted = true } }
        waitFor { restarted }
        XCTAssertEqual(f.producers.count, 1)
        XCTAssertEqual(f.published, 2)
        XCTAssertEqual(f.retired, 1)
    }

    func testExplicitRetryRecreatesFailedProducerAndRetiresItsVirtualInput() {
        let failed = """
            printf '{"ready":true}\n'
            IFS= read -r command
            printf '{"failed":true,"reason":"fixture-failure"}\n'
            while IFS= read -r command; do :; done
            """
        let f = Fixture([failed, good]); defer { f.cleanup() }
        var failure = false
        f.session.start(.init(input: nil, apps: [])) { if case .failure = $0 { failure = true } }
        waitFor { failure }
        XCTAssertFalse(f.producers[0].isRunning, "A retry cannot overlap a failed capture")
        XCTAssertEqual(f.retired, 1, "Failure must withdraw the unusable public input before reporting completion")
        var succeeded = false
        f.session.start(.init(input: nil, apps: [])) { if case .success = $0 { succeeded = true } }
        waitFor { succeeded }
        XCTAssertEqual(f.producers.count, 2)
        XCTAssertEqual(f.published, 2)
        XCTAssertEqual(f.retired, 1)
    }

    func testAcknowledgementTimeoutReapsProducerAndCanBeRetriedExplicitly() {
        let blocked = "printf '{\"ready\":true}\\n'\nwhile IFS= read -r command; do :; done"
        let f = Fixture([blocked, good]); defer { f.cleanup() }
        var failed = false
        f.session.start(.init(input: nil, apps: [])) { if case .failure = $0 { failed = true } }
        waitFor({ failed }, timeout: 10)
        XCTAssertFalse(f.producers[0].isRunning)
        var succeeded = false
        f.session.start(.init(input: nil, apps: [])) { if case .success = $0 { succeeded = true } }
        waitFor { succeeded }
        XCTAssertEqual(f.producers.count, 2)
        XCTAssertEqual(f.retired, 1)
    }

    func testFailureAfterInitialAcknowledgementStillStopsTheRunningSession() {
        let laterFailure = """
            printf '{"ready":true}\n'
            IFS= read -r command
            printf '{"applied":1,"captureCount":0}\n'
            IFS= read -r command
            printf '{"failed":true,"reason":"fixture-update-failure"}\n'
            while IFS= read -r command; do :; done
            """
        let f = Fixture([laterFailure]); defer { f.cleanup() }
        var started = false
        var failed = false
        f.session.start(.init(input: nil, apps: [])) {
            switch $0 { case .success: started = true; case .failure: failed = true }
        }
        waitFor { started }
        f.session.update(.init(input: nil, apps: []))
        waitFor { failed }
        XCTAssertFalse(f.producers[0].isRunning)
    }

    func testCancellingStartReapsProducerBeforeReturningAndAllowsFreshStart() {
        for ready in [false, true] {
            let blocked = (ready ? "printf '{\"ready\":true}\\n'\n" : "") + "while IFS= read -r command; do :; done"
            let f = Fixture([blocked, good]); defer { f.cleanup() }
            var cancelledResults = 0
            f.session.start(.init(input: nil, apps: [])) { _ in cancelledResults += 1 }
            if ready { waitFor { f.published == 1 } }
            f.session.stop()
            XCTAssertFalse(f.producers[0].isRunning, "Closing during startup must reap the producer immediately")
            XCTAssertEqual(f.retired, ready ? 1 : 0, "Cancelled startup cannot leave its virtual input available")
            var succeeded = false
            var lateFailure = false
            f.session.start(.init(input: nil, apps: [])) {
                switch $0 { case .success: succeeded = true; case .failure: lateFailure = true }
            }
            waitFor { succeeded || lateFailure }
            XCTAssertTrue(succeeded)
            XCTAssertFalse(lateFailure, "Events queued by the retired producer cannot poison its replacement")
            XCTAssertEqual(cancelledResults, 0)
        }
    }

    func testStopDuringBlockedLiveUpdateReapsProducerBeforeCompleting() {
        let blockedUpdate = """
            printf '{"ready":true}\n'
            IFS= read -r command
            printf '{"applied":1,"captureCount":0}\n'
            while IFS= read -r command; do :; done
            """
        let f = Fixture([blockedUpdate]); defer { f.cleanup() }
        var started = false
        f.session.start(.init(input: nil, apps: [])) { if case .success = $0 { started = true } }
        waitFor { started }
        f.session.update(.init(input: nil, apps: []))
        var stopped = false
        f.session.stop { if case .success = $0 { stopped = true } }
        XCTAssertTrue(stopped)
        XCTAssertFalse(f.producers[0].isRunning)
        XCTAssertEqual(f.retired, 1)
    }

    func testNormalStopCompletesOnlyAfterEmptyCaptureAcknowledgement() {
        let delayedStop = """
            printf '{"ready":true}\n'
            IFS= read -r command
            printf '{"applied":1,"captureCount":0}\n'
            IFS= read -r command
            sleep 0.15
            printf '{"applied":2,"captureCount":0}\n'
            while IFS= read -r command; do :; done
            """
        let f = Fixture([delayedStop]); defer { f.cleanup() }
        var started = false
        f.session.start(.init(input: nil, apps: [])) { if case .success = $0 { started = true } }
        waitFor { started }
        var stopped = false
        f.session.stop { if case .success = $0 { stopped = true } }
        XCTAssertFalse(stopped)
        XCTAssertEqual(f.retired, 0, "Pending stop waits for the actual empty-capture acknowledgement")
        waitFor { stopped }
        XCTAssertTrue(f.producers[0].isRunning, "The idle producer may stay ready without publishing an input")
        XCTAssertEqual(f.retired, 1)
    }
    func testFailedRepublicationAfterStopCannotClaimReadyOrLeaveProducerRunning() {
        let f = Fixture([good]); defer { f.cleanup() }
        var started = false
        f.session.start(.init(input: nil, apps: [])) { if case .success = $0 { started = true } }
        waitFor { started }
        var stopped = false
        f.session.stop { if case .success = $0 { stopped = true } }
        waitFor { stopped }
        f.publishFailureAt = 2
        var failed = false
        f.session.start(.init(input: nil, apps: [])) {
            switch $0 { case .success: XCTFail("A missing virtual input is not ready"); case .failure: failed = true }
        }
        waitFor { failed }
        XCTAssertEqual(f.retired, 1)
        XCTAssertFalse(f.producers[0].isRunning)
    }

    func testStoppedSessionRejectsUpdatesWithoutRepublishingOrRecapturing() {
        let f = Fixture([good]); defer { f.cleanup() }
        var started = false
        f.session.start(.init(input: nil, apps: [])) { if case .success = $0 { started = true } }
        waitFor { started }
        var stopped = false
        f.session.stop { if case .success = $0 { stopped = true } }
        waitFor { stopped }
        var rejected = false
        f.session.update(.init(input: nil, apps: [])) {
            switch $0 { case .success: XCTFail("Only an explicit Start may reactivate a stopped session"); case .failure: rejected = true }
        }
        waitFor { rejected }
        XCTAssertEqual(f.published, 1)
        XCTAssertEqual(f.retired, 1)
    }

    func testFailedWithdrawalRejectsStopAndPreservesCleanupForExplicitRetry() {
        let f = Fixture([good, good]); defer { f.cleanup() }
        var started = false
        f.session.start(.init(input: nil, apps: [])) { if case .success = $0 { started = true } }
        waitFor { started }
        f.retirementFailures = 1
        var rejected = false
        f.session.stop {
            switch $0 { case .success: XCTFail("Failed device removal cannot confirm Off"); case .failure: rejected = true }
        }
        waitFor { rejected }
        XCTAssertFalse(f.producers[0].isRunning)
        XCTAssertEqual(f.retirementAttempts, 1)
        XCTAssertEqual(f.retired, 0)
        var restarted = false
        f.session.start(.init(input: nil, apps: [])) { if case .success = $0 { restarted = true } }
        waitFor { restarted }
        XCTAssertEqual(f.retirementAttempts, 2)
        XCTAssertEqual(f.retired, 1)
        XCTAssertEqual(f.published, 2)
    }

}
