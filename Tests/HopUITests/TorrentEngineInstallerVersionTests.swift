import CryptoKit
import AppKit
import SwiftUI
import XCTest
@testable import Hop
import HopCore

final class TorrentEngineInstallerVersionTests: XCTestCase {
    @MainActor
    func testStockEngineRequiresSelectiveStorageUpdate() {
        XCTAssertTrue(ToolVersion.isBelow("9.0.1", minimum: TorrentEngineInstaller.minimumVersion))
        XCTAssertFalse(ToolVersion.isBelow("9.0.1.1", minimum: TorrentEngineInstaller.minimumVersion))
    }
    @MainActor
    func testRequiredDigestIsRecheckedBeforeLaunchWithoutDeletingChangedBinary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let binary = root.appendingPathComponent("rqbit")
        let bytes = Data("approved test engine".utf8)
        try bytes.write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let installer = FailedUpdateInstaller(binary: binary, version: "9.0.1.1", digest: digest)
        XCTAssertFalse(installer.needsUpdate)
        XCTAssertEqual(installer.runnableBinaryURL(), binary)
        let changed = Data("changed engine".utf8)
        try changed.write(to: binary)
        XCTAssertNil(installer.runnableBinaryURL())
        XCTAssertTrue(installer.needsUpdate)
        XCTAssertEqual(try Data(contentsOf: binary), changed)
    }

    private static var retainedFixtures: [AnyObject] = []

    @MainActor
    func testRequiredUpdateRetryWorksWithSavedTorrents() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let binary = root.appendingPathComponent("rqbit")
        try Data("old engine".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let installer = FailedUpdateInstaller(binary: binary, version: "9.0.1")
        await installer.updateIfNeeded()
        XCTAssertEqual(installer.attempts, 1)
        let controller = TorrentController(installer: installer)
        controller.loadDemo()
        let model = AppModel(preview: true)
        let savedTheme = UserDefaults.standard.object(forKey: Theme.themeKey)
        defer { UserDefaults.standard.set(savedTheme, forKey: Theme.themeKey) }
        for lang in [AppLanguage.en, .ru] {
            for dark in [false, true] {
                UserDefaults.standard.set(dark ? "dark" : "light", forKey: Theme.themeKey)
                let host = NSHostingView(rootView: TorrentView(torrent: controller, lang: lang)
                    .environmentObject(model).frame(width: 368).background(Theme.background))
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.frame.size = host.fittingSize
                let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 200, y: 200), size: host.frame.size),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                Self.retainedFixtures.append(contentsOf: [model as AnyObject, controller as AnyObject, host, window])
                defer { window.orderOut(nil) }
                host.layoutSubtreeIfNeeded()
                XCTAssertGreaterThan(host.bounds.height, 70)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if let directory = ProcessInfo.processInfo.environment["HOP_PATCH_RENDER_DIR"] {
                    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                        to: URL(fileURLWithPath: directory).appendingPathComponent("engine-retry-\(lang.rawValue)-\(dark ? "dark" : "light").png"))
                }
                if lang == .en && !dark {
                    let y: CGFloat = host.isFlipped ? 16 : host.bounds.maxY - 16
                    let point = host.convert(NSPoint(x: host.bounds.midX, y: y), to: nil)
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                            clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)))
                    }
                    try await Task.sleep(for: .milliseconds(100))
                    XCTAssertEqual(installer.attempts, 2)
                    XCTAssertEqual(controller.torrents.count, 1)
                    XCTAssertEqual(installer.installedVersion, "9.0.1")
                }
            }
        }
    }

    @MainActor
    func testFailedRequiredUpdateNeverLaunchesOldEngineOrCreatesOutput() async throws {
        for version in [nil, "9.0.1", "9.0.1.1"] as [String?] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let marker = root.appendingPathComponent("launched")
            let binary = root.appendingPathComponent("rqbit")
            let script = "#!/bin/sh\necho launched > '\(marker.path)'\nexit 97\n"
            try script.write(to: binary, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
            let installer = FailedUpdateInstaller(binary: binary, version: version)
            let controller = TorrentController(installer: installer)
            defer { controller.stopEngine() }
            let output = root.appendingPathComponent("output")
            let oldDownload = UserDefaults.standard.object(forKey: TorrentController.downloadDirKey)
            UserDefaults.standard.set(output.path, forKey: TorrentController.downloadDirKey)
            defer { UserDefaults.standard.set(oldDownload, forKey: TorrentController.downloadDirKey) }
            do {
                try await controller.ensureEngine()
                XCTFail("An engine below the required version must not start")
            } catch {
                XCTAssertTrue(error is TorrentController.EngineUnavailable, "\(error)")
            }
            XCTAssertEqual(installer.attempts, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertEqual(try String(contentsOf: binary, encoding: .utf8), script)
            XCTAssertEqual(installer.installedVersion, version)
        }
    }
}

@MainActor
private final class FailedUpdateInstaller: ToolInstaller {
    let fixtureBinary: URL
    let fixtureVersion: String?
    private(set) var attempts = 0

    init(binary: URL, version: String?, digest: String = TorrentEngineInstaller.requiredSHA256) {
        fixtureBinary = binary
        fixtureVersion = version
        super.init(manifestURL: TorrentEngineInstaller.manifestURL,
                   folderName: "unused-test-engine", binaryName: "rqbit",
                   minimumVersion: TorrentEngineInstaller.minimumVersion, publicKeyBase64: "", requiredSHA256: digest)
    }

    override var binaryURL: URL { fixtureBinary }
    override var installedVersion: String? { fixtureVersion }

    override func install() async {
        attempts += 1
        await super.install()
    }
}
