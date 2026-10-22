import XCTest
@testable import Hop

@MainActor
final class LidDisplayControllerTests: XCTestCase {
    @MainActor
    private final class Display {
        var closed: Bool? = false
        var external: Bool? = false
        var sleepSucceeds = true
        var wakeSucceeds = true
        var events: [String] = []

        func controller() -> LidDisplayController {
            LidDisplayController(environment: .init(
                lidClosed: { self.closed },
                externalDisplayConnected: { self.external },
                sleepDisplays: { self.events.append("sleep"); return self.sleepSucceeds },
                wakeDisplays: { self.events.append("wake"); return self.wakeSucceeds },
                dimBuiltin: { self.events.append("dim") },
                restoreBuiltin: { self.events.append("restore") }
            ))
        }
    }

    func testClosingSleepsOnceAndOpeningWakesOnce() {
        let display = Display()
        let controller = display.controller()
        controller.start()
        defer { controller.stop() }
        XCTAssertTrue(display.events.isEmpty)
        display.closed = true
        controller.refresh()
        controller.refresh()
        XCTAssertEqual(display.events, ["sleep"])
        display.closed = false
        controller.refresh()
        controller.refresh()
        XCTAssertEqual(display.events, ["sleep", "wake"])
    }

    func testStartingWithTheLidClosedSleepsImmediately() {
        let display = Display()
        display.closed = true
        let controller = display.controller()
        controller.start()
        defer { controller.stop() }
        XCTAssertEqual(display.events, ["sleep"])
    }

    func testExternalDisplayOnlyDimsBuiltin() {
        let display = Display()
        display.external = true
        display.closed = true
        let controller = display.controller()
        controller.start()
        defer { controller.stop() }
        controller.refresh()
        XCTAssertEqual(display.events, ["dim"])
        display.closed = false
        controller.refresh()
        XCTAssertEqual(display.events, ["dim", "restore"])
    }

    func testPluggingAndUnpluggingExternalDisplayWhileClosed() {
        let display = Display()
        display.closed = true
        let controller = display.controller()
        controller.start()
        defer { controller.stop() }
        display.external = true
        controller.refresh()
        XCTAssertEqual(display.events, ["sleep", "wake", "dim"])
        display.external = false
        controller.refresh()
        XCTAssertEqual(display.events, ["sleep", "wake", "dim", "restore", "sleep"])
    }

    func testFailedSleepDimsWithoutSpawningRepeatedCommands() {
        let display = Display()
        display.closed = true
        display.sleepSucceeds = false
        let controller = display.controller()
        controller.start()
        defer { controller.stop() }
        controller.refresh()
        controller.refresh()
        XCTAssertEqual(display.events, ["sleep", "dim"])
        display.closed = false
        controller.refresh()
        XCTAssertEqual(display.events, ["sleep", "dim", "restore"])
        display.closed = true
        display.sleepSucceeds = true
        controller.refresh()
        XCTAssertEqual(display.events, ["sleep", "dim", "restore", "sleep"])
    }

    func testFailedWakeIsRetriedBeforeDimmingExternalConfiguration() {
        let display = Display()
        display.closed = true
        let controller = display.controller()
        controller.start()
        defer { controller.stop() }
        display.external = true
        display.wakeSucceeds = false
        controller.refresh()
        XCTAssertEqual(display.events, ["sleep", "wake"])
        display.wakeSucceeds = true
        controller.refresh()
        XCTAssertEqual(display.events, ["sleep", "wake", "wake", "dim"])
    }

    func testUnknownDisplayInventoryDoesNotSleep() {
        let display = Display()
        display.closed = true
        display.external = nil
        let controller = display.controller()
        controller.start()
        defer { controller.stop() }
        XCTAssertTrue(display.events.isEmpty)
        display.external = false
        controller.refresh()
        XCTAssertEqual(display.events, ["sleep"])
    }

    func testUnknownLidStateDoesNotWakeSleepingDisplay() {
        let display = Display()
        display.closed = true
        let controller = display.controller()
        controller.start()
        defer { controller.stop() }
        display.closed = nil
        controller.refresh()
        XCTAssertEqual(display.events, ["sleep"])
    }

    func testStoppingWhileClosedDoesNotWakeDisplay() {
        let display = Display()
        display.closed = true
        let controller = display.controller()
        controller.start()
        controller.stop()
        display.closed = false
        controller.refresh()
        XCTAssertEqual(display.events, ["sleep"])
    }

    func testStoppingWithAnOpenLidWakesOwnedDisplay() {
        let display = Display()
        display.closed = true
        let controller = display.controller()
        controller.start()
        display.closed = false
        controller.stop()
        XCTAssertEqual(display.events, ["sleep", "wake"])
    }

    func testStoppingRestoresDimmingAndRestartRechecksState() {
        let display = Display()
        display.closed = true
        display.external = true
        let controller = display.controller()
        controller.start()
        controller.stop()
        controller.start()
        controller.stop()
        XCTAssertEqual(display.events, ["dim", "restore", "dim", "restore"])
    }

    func testRestartRetriesWakeThatFailedDuringStop() {
        let display = Display()
        display.closed = true
        let controller = display.controller()
        controller.start()
        display.closed = false
        display.wakeSucceeds = false
        controller.stop()
        display.wakeSucceeds = true
        controller.start()
        controller.stop()
        XCTAssertEqual(display.events, ["sleep", "wake", "wake"])
    }
}
