import CoreML
import CryptoKit
import Foundation

enum MediaModelStore {
    static let hash = "5a59e554794371b95fe61274b8a2040f1b3e274479abf15595dcdad0535afad4"
    static let remote = URL(string: "https://huggingface.co/VincentGOURBIN/RealESRGAN-CoreML/resolve/da0d01ce79946e6a62563eaf900ff9844af1f67f/RealESRGAN-x4v3.mlpackage.zip")!
    static var compiled: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hop/Media/\(hash).mlmodelc", isDirectory: true)
    }
    static var ready: Bool { FileManager.default.fileExists(atPath: compiled.appendingPathComponent("coremldata.bin").path) }
    static func validArchive(_ data: Data) -> Bool {
        data.count <= 3_000_000 && SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == hash
    }
    static func install() async throws {
        guard #available(macOS 15, *) else { throw MediaFailure.model }
        let (download, response) = try await URLSession.shared.download(from: remote)
        defer { try? FileManager.default.removeItem(at: download) }
        guard let bytes = try download.resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes <= 3_000_000 else { throw MediaFailure.download }
        let data = try Data(contentsOf: download, options: .mappedIfSafe)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200, validArchive(data) else { throw MediaFailure.download }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("hop-media-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archive = scratch.appendingPathComponent("model.zip")
        try data.write(to: archive)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, scratch.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw MediaFailure.model }
        try Task.checkCancellation()
        let result = try await MLModel.compileModel(at: scratch.appendingPathComponent("RealESRGAN-x4v3.mlpackage"))
        defer { try? FileManager.default.removeItem(at: result) }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: compiled.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: compiled.path) { try FileManager.default.removeItem(at: compiled) }
        try FileManager.default.moveItem(at: result, to: compiled)
    }
}
