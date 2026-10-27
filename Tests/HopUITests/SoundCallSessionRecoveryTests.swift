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
            return { [unowned self] in retired += 1 }
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

    func testNormalStartCanReusePreparedProducerAfterStop() {
        let f = Fixture([good]); defer { f.cleanup() }
        var started = false
        f.session.start(.init(input: nil, apps: [])) { if case .success = $0 { started = true } }
        waitFor { started }
        f.session.stop()
        var restarted = false
        f.session.start(.init(input: nil, apps: [])) { if case .success = $0 { restarted = true } }
        waitFor { restarted }
        XCTAssertEqual(f.producers.count, 1)
        XCTAssertEqual(f.published, 1)
        XCTAssertEqual(f.retired, 0)
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
            XCTAssertEqual(f.retired, ready ? 1 : 0)
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
}
