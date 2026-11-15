import Foundation
import HopHardwareKit

// Developer installation uses the same maintenance barrier as the built-in updater.
@MainActor
enum HardwareDiagnostics {
    static func runIfRequested() {
        let flags = Set(CommandLine.arguments.dropFirst())
        let commands: Set<String> = ["--hardware-check", "--hardware-register", "--hardware-prepare-update"]
        guard !flags.isDisjoint(with: commands) else { return }
        guard Bundle.main.bundleIdentifier == "com.antonshakirov.minimo.dev", flags.count == 1 else { exit(1) }
        Task { @MainActor in
            do {
                let service = SystemCoolingService()
                if flags.contains("--hardware-prepare-update") {
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
