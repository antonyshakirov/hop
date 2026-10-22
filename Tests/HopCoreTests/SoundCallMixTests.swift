import Foundation
import XCTest
@testable import HopCore

final class SoundCallMixTests: XCTestCase {
    func testAReusedProcessCannotCaptureAnotherApplication() {
        XCTAssertTrue(SoundCallMixPolicy.ownsProcess("com.google.Chrome.helper", selectedBundle: "com.google.Chrome"))
        XCTAssertFalse(SoundCallMixPolicy.ownsProcess("com.apple.Safari", selectedBundle: "com.google.Chrome"))
        XCTAssertFalse(SoundCallMixPolicy.ownsProcess("com.google.ChromeOther", selectedBundle: "com.google.Chrome"))
        XCTAssertFalse(SoundCallMixPolicy.ownsProcess("us.zoom.xos", selectedBundle: "us.zoom.xos"))
    }
    func testWorkerRetainsIndependentApplicationSendSettings() throws {
        let data = Data(#"{"start":true,"meters":false,"inputs":[],"apps":[{"id":"com.google.Chrome","processes":[123],"settings":{"gain":0.25,"muted":false,"bass":false,"active":true}}],"requestID":42}"#.utf8)
        let command = try JSONDecoder().decode(SoundWorkerCommand.self, from: data)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any])
        let apps = try XCTUnwrap(encoded["apps"] as? [[String: Any]])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?["id"] as? String, "com.google.Chrome")
        XCTAssertEqual(encoded["requestID"] as? Int, 42)
        let settings = try XCTUnwrap(apps.first?["settings"] as? [String: Any])
        XCTAssertEqual(settings["gain"] as? Double, 0.25)
    }
}
