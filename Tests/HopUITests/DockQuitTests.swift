import AppKit
import XCTest
@testable import Hop

@MainActor
final class DockQuitTests: XCTestCase {
    private func event(reason: OSType? = nil,
                       eventID: AEEventID = AEEventID(kAEQuitApplication)) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                                          eventID: eventID, targetDescriptor: nil,
                                          returnID: AEReturnID(kAutoGenerateReturnID),
                                          transactionID: AETransactionID(kAnyTransactionID))
        if let reason {
            event.setAttribute(NSAppleEventDescriptor(typeCode: reason),
                               forKeyword: AEKeyword(kAEQuitReason))
        }
        return event
    }

    func testDockQuitKeepsHopRunningEvenAfterItsLastWindowDisappears() {
        let delegate = AppDelegate()
        XCTAssertEqual(delegate.terminationReply(event: event(),
            senderBundleIdentifier: "com.apple.dock"), .terminateCancel)
    }

    func testRepeatedDockQuitStillKeepsHopRunning() {
        let delegate = AppDelegate()
        for _ in 0..<3 {
            XCTAssertEqual(delegate.terminationReply(event: event(),
                senderBundleIdentifier: "com.apple.dock"), .terminateCancel)
        }
    }

    func testSystemSessionTerminationFromDockStillWorks() {
        let delegate = AppDelegate()
        for reason in [kAEQuitAll, kAEShutDown, kAERestart, kAEReallyLogOut] {
            XCTAssertEqual(delegate.terminationReply(event: event(reason: OSType(reason)),
                senderBundleIdentifier: "com.apple.dock"), .terminateNow)
        }
    }

    func testQuitFromOtherApplicationsStillWorks() {
        let delegate = AppDelegate()
        for sender in ["com.apple.loginwindow", "com.apple.finder", "com.antonshakirov.minimo"] {
            XCTAssertEqual(delegate.terminationReply(event: event(),
                senderBundleIdentifier: sender), .terminateNow)
        }
    }

    func testInternalQuitWithoutAppleEventStillWorks() {
        XCTAssertEqual(AppDelegate().terminationReply(event: nil,
            senderBundleIdentifier: nil), .terminateNow)
    }

    func testNonQuitEventFromDockDoesNotChangeTermination() {
        XCTAssertEqual(AppDelegate().terminationReply(event: event(eventID: AEEventID(kAEOpenApplication)),
            senderBundleIdentifier: "com.apple.dock"), .terminateNow)
    }

    func testDockQuitClosesVisibleWindow() {
        let window = window()
        window.orderFront(nil)
        defer { window.close() }
        XCTAssertTrue(window.isVisible)
        let reply = AppDelegate().terminationReply(event: event(),
            senderBundleIdentifier: "com.apple.dock", windows: [window])
        XCTAssertEqual(reply, .terminateCancel)
        XCTAssertFalse(window.isVisible)
    }

    func testDockQuitClosesMinimizedWindow() {
        let window = window()
        window.orderFront(nil)
        window.miniaturize(nil)
        defer { window.close() }
        let deadline = Date().addingTimeInterval(3)
        while !window.isMiniaturized && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(window.isMiniaturized)
        XCTAssertEqual(AppDelegate().terminationReply(event: event(),
            senderBundleIdentifier: "com.apple.dock", windows: [window]), .terminateCancel)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isMiniaturized)
    }

    func testDockQuitRespectsWindowCloseCancellation() {
        let window = window()
        let veto = CloseVeto()
        window.delegate = veto
        window.orderFront(nil)
        defer { window.close() }
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(AppDelegate().terminationReply(event: event(),
            senderBundleIdentifier: "com.apple.dock", windows: [window]), .terminateCancel)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(veto.requests, 1)
    }

    func testSessionReasonAsParameterStillAllowsTermination() {
        let event = event()
        event.setParam(NSAppleEventDescriptor(typeCode: OSType(kAEShutDown)),
                       forKeyword: AEKeyword(kAEQuitReason))
        XCTAssertEqual(AppDelegate().terminationReply(event: event,
            senderBundleIdentifier: "com.apple.dock"), .terminateNow)
    }

    private func window() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 100),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private final class CloseVeto: NSObject, NSWindowDelegate {
        var requests = 0
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            requests += 1
            return false
        }
    }

    func testClosingLastWindowDoesNotTerminateHop() {
        XCTAssertFalse(AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
