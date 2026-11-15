import Foundation
import XCTest
@testable import Hop

final class HardwareBundleValidationTests: XCTestCase {
    func testIntegrityValidAdHocBundleIsRejectedBeforeServiceReplacement() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("hardware-signature-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Hop.app")
        let helper = app.appendingPathComponent("Contents/Helpers/HopHardwareHelper.app")
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let binary = repo.appendingPathComponent(".build/debug/HopHardwareHelper")
        for (url, name, identifier) in [(app, "Hop", "com.antonshakirov.minimo"),
            (helper, "HopHardwareHelper", "com.antonshakirov.minimo.hardware-helper")] {
            let macOS = url.appendingPathComponent("Contents/MacOS")
            try manager.createDirectory(at: macOS, withIntermediateDirectories: true)
            try manager.copyItem(at: binary, to: macOS.appendingPathComponent(name))
            let info = ["CFBundleIdentifier": identifier, "CFBundleExecutable": name,
                        "CFBundlePackageType": "APPL", "CFBundleVersion": "1"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: url.appendingPathComponent("Contents/Info.plist"))
        }
        try command(["--force", "--sign", "-", helper.path])
        try command(["--force", "--sign", "-", app.path])
        try command(["--verify", "--deep", "--strict", app.path])
        XCTAssertThrowsError(try HardwareBundleValidation.validate(app,
            identifier: "com.antonshakirov.minimo", team: "ABCDEFGHIJ"))
    }

    private func command(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
    }
}
