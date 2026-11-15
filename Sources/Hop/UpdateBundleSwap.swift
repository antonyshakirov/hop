import Darwin
import Foundation

// SPEC: docs/spec.md — Hardware service updates.
struct UpdateBundleSwap {
    let installed: URL
    let candidate: URL
    private(set) var exchanged = false

    mutating func exchange() throws {
        guard installed.deletingLastPathComponent().resolvingSymlinksInPath()
                == candidate.deletingLastPathComponent().resolvingSymlinksInPath(),
              installed != candidate else { throw CocoaError(.fileWriteInvalidFileName) }
        let manager = FileManager.default
        for url in [installed, candidate] {
            guard try manager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory
            else { throw CocoaError(.fileWriteInvalidFileName) }
        }
        guard renameatx_np(AT_FDCWD, installed.path, AT_FDCWD, candidate.path, UInt32(RENAME_SWAP)) == 0
        else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        exchanged.toggle()
    }

    mutating func rollback() throws {
        if exchanged { try exchange() }
    }
}
