import CryptoKit
import Foundation

struct TorrentSourceFile: Codable, Equatable {
    let path: String
    let digest: String

    init(url: URL, data: Data) {
        path = url.standardizedFileURL.path
        digest = Self.hash(data)
    }

    func trash(using move: (URL) throws -> Void = {
        try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }) throws {
        guard path.hasPrefix("/"), URL(fileURLWithPath: path).pathExtension.lowercased() == "torrent" else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let url = URL(fileURLWithPath: path)
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        guard Self.hash(try Data(contentsOf: url)) == digest else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try move(url)
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
