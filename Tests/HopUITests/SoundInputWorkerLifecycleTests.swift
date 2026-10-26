import XCTest
import HopAudioEngine

@MainActor
final class SoundInputWorkerLifecycleTests: XCTestCase {
    private enum RestartFailure: Error { case unavailable }

    func testSuccessfulConfigurationRestartPreservesCaptureWithoutReportingFailure() {
        let lifecycle = SoundInputWorkerLifecycle()
        let generation = lifecycle.begin()
        var restarts = 0, failures = 0
        var capturing = true

        lifecycle.configurationChanged(generation: generation, restart: { restarts += 1 }, silence: {
            capturing = false
        }, failed: { failures += 1 })

        XCTAssertEqual(restarts, 1)
        XCTAssertTrue(capturing, "A successful output-engine restart must preserve selected captures")
        XCTAssertEqual(failures, 0, "A configuration notification alone is not a worker failure")
    }

    func testFailedConfigurationRestartSilencesCaptureAndReportsFailure() {
        let lifecycle = SoundInputWorkerLifecycle()
        let generation = lifecycle.begin()
        var restarts = 0, silences = 0, failures = 0

        lifecycle.configurationChanged(generation: generation, restart: {
            restarts += 1
            throw RestartFailure.unavailable
        }, silence: { silences += 1 }, failed: { failures += 1 })

        XCTAssertEqual(restarts, 1)
        XCTAssertEqual(silences, 1)
        XCTAssertEqual(failures, 1)
    }

    func testQueuedConfigurationNotificationAfterStopIsIgnored() {
        let lifecycle = SoundInputWorkerLifecycle()
        let generation = lifecycle.begin()
        lifecycle.stop()
        var restarts = 0, silences = 0, failures = 0

        lifecycle.configurationChanged(generation: generation, restart: { restarts += 1 },
            silence: { silences += 1 }, failed: { failures += 1 })

        XCTAssertEqual(restarts, 0, "A queued notification must not restart a stopped worker")
        XCTAssertEqual(silences, 0)
        XCTAssertEqual(failures, 0)
    }

    func testOldGenerationCannotAffectNewlyPreparedWorker() {
        let lifecycle = SoundInputWorkerLifecycle()
        let oldGeneration = lifecycle.begin()
        lifecycle.stop()
        let currentGeneration = lifecycle.begin()
        var restarts = 0, silences = 0, failures = 0

        lifecycle.configurationChanged(generation: oldGeneration, restart: { restarts += 1 },
            silence: { silences += 1 }, failed: { failures += 1 })

        XCTAssertEqual(restarts, 0)
        XCTAssertEqual(silences, 0)
        XCTAssertEqual(failures, 0)

        lifecycle.configurationChanged(generation: currentGeneration, restart: { restarts += 1 },
            silence: { silences += 1 }, failed: { failures += 1 })

        XCTAssertEqual(restarts, 1)
        XCTAssertEqual(silences, 0)
        XCTAssertEqual(failures, 0)
    }

    func testTerminalRestartFailureIgnoresFurtherNotificationsFromSameGeneration() {
        let lifecycle = SoundInputWorkerLifecycle()
        let generation = lifecycle.begin()
        var restarts = 0, silences = 0, failures = 0

        lifecycle.configurationChanged(generation: generation, restart: {
            restarts += 1
            throw RestartFailure.unavailable
        }, silence: { silences += 1 }, failed: { failures += 1 })
        lifecycle.configurationChanged(generation: generation, restart: { restarts += 1 },
            silence: { silences += 1 }, failed: { failures += 1 })

        XCTAssertEqual(restarts, 1)
        XCTAssertEqual(silences, 1)
        XCTAssertEqual(failures, 1)
    }
}
