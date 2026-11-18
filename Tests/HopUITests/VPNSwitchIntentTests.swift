import HopCore
import XCTest
@testable import Hop

@MainActor
final class VPNSwitchIntentTests: XCTestCase {
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var state = "Connected"
        var startOK = true
        var gate: DispatchSemaphore?
        var calls: [[String]] = []
    }

    private nonisolated static func list(_ state: String) -> String {
        "Available network connection services in the current set (*=enabled):\n"
        + "* (\(state))   6A7852E0-3E2A-4C8B-82BA-33132F2B3197 VPN (com.vendor.app) \"Home\"   [VPN:com.vendor.app]\n"
    }

    private func make(_ box: Box) -> VPNController {
        VPNController(runner: { args in
            box.lock.lock(); box.calls.append(args); box.lock.unlock()
            if args.contains("list") { return (Self.list(box.state), true) }
            if args.contains("start") { box.gate?.wait(); return ("", box.startOK) }
            if args.contains("stop") { box.gate?.wait(); return ("", true) }
            return ("", true)
        })
    }

    private func settle(_ vpn: VPNController, _ done: () -> Bool) async {
        for _ in 0..<400 where !done() { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    func testSwitchFlipsOnClickBeforeTheCommandReturns() async {
        let box = Box(); box.gate = DispatchSemaphore(value: 0)
        let vpn = make(box)
        vpn.refresh()
        await settle(vpn) { !vpn.configurations.isEmpty }
        let row = vpn.configurations[0]
        XCTAssertTrue(vpn.shownOn(row))
        vpn.toggle(row)
        XCTAssertFalse(vpn.shownOn(row))
        box.gate?.signal()
    }

    func testRefusedStartGivesTheSwitchBack() async {
        let box = Box(); box.state = "Disconnected"; box.startOK = false
        let vpn = make(box)
        vpn.refresh()
        await settle(vpn) { !vpn.configurations.isEmpty }
        let row = vpn.configurations[0]
        XCTAssertFalse(vpn.shownOn(row))
        vpn.toggle(row)
        XCTAssertTrue(vpn.shownOn(row))
        await settle(vpn) { vpn.pending.isEmpty }
        XCTAssertFalse(vpn.shownOn(row))
    }

    func testStaleReplyCannotOverrideANewerClick() async {
        let box = Box(); box.gate = DispatchSemaphore(value: 0)
        let vpn = make(box)
        vpn.refresh()
        await settle(vpn) { !vpn.configurations.isEmpty }
        let row = vpn.configurations[0]
        vpn.toggle(row)            // off
        vpn.toggle(row)            // back on, before the first command returned
        XCTAssertTrue(vpn.shownOn(row))
        box.gate?.signal(); box.gate?.signal()
        await settle(vpn) { box.lock.lock(); defer { box.lock.unlock() }; return box.calls.filter { $0.contains("start") }.count == 1 }
        XCTAssertTrue(vpn.shownOn(row))
    }
}
