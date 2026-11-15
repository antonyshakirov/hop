import Foundation
import XCTest
@testable import Hop

@MainActor
final class HardwareNotificationTests: XCTestCase {
    func testHeadlessCutoffNoticeDoesNotAskUserNotificationsForAnApplicationProxy() {
        XCTAssertNotEqual(Bundle.main.bundleURL.pathExtension, "app")
        let wasSnapshot = Snapshot.active
        Snapshot.active = false
        defer { Snapshot.active = wasSnapshot }
        Alerts.noticeIfAllowed(title: "Cooling", body: "The protected session stopped.")
    }
}
