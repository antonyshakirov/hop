import Foundation
import HopHardwareKit

// Developer installation uses the same maintenance barrier as the built-in updater.
@MainActor
enum HardwareDiagnostics {
    static func runIfRequested() {
        let flags = Set(CommandLine.arguments.dropFirst())
        let commands: Set<String> = ["--hardware-check", "--hardware-register", "--hardware-prepare-update", "--hardware-update-check"]
        guard !flags.isDisjoint(with: commands) else { return }
        guard Bundle.main.bundleIdentifier == "com.antonshakirov.minimo.dev", flags.count == 1 else { exit(1) }
        Task { @MainActor in
            do {
                let service = SystemCoolingService()
                if flags.contains("--hardware-update-check") {
                    let controller = CoolingController(service: service)
                    var result: [String: Any] = ["controller": controller.updateDiagnosticState,
                                                "service": String(describing: service.state)]
                    result["lockDirectory"] = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("com.antonshakirov.minimo.dev/update-locks").path
                    var lockError: Int32?
                    do {
                        let lock = try AppProcessLock.acquire("hardware", createIfMissing: false, onFlock: { lockError = $0 })
                        lock.release(); result["existingLockAcquired"] = true
                    } catch {
                        result["existingLockAcquired"] = false
                        result["lockFailure"] = (error as? HardwareReason)?.rawValue ?? "unknown"
                    }
                    result["flockErrno"] = lockError.map(Int.init) ?? -1
                    print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
                } else if flags.contains("--hardware-prepare-update") {
                    let controller = CoolingController(service: service)
                    try await controller.prepareUpdate()
                    print("hardware: maintenance ready")
                } else {
                    if flags.contains("--hardware-register") { try service.register() }
                    print("hardware: \(service.state)")
                    if service.state == .enabled {
                        let status = try await service.request(.init(.status))
                        print(String(decoding: try JSONEncoder().encode(status), as: UTF8.self))
                        guard status.reason == nil || status.reason == .stopped else { exit(1) }
                    }
                }
                exit(0)
            } catch {
                let error = error as NSError
                print("hardware: failed \(error.domain) / \(error.code)")
                exit(1)
            }
        }
        RunLoop.main.run()
    }
}
