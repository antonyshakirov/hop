import AppKit
import HopHardwareKit

extension CoolingController {
    private struct LocalReadings: Encodable {
        let fans: [FanReading]
        let temperature: Double?
        let availability: FanAvailability?
        let keys: [FanKeyReading]
    }
    private struct Diagnostic: Encodable {
        let appVersion: String
        let model: String?
        let macOS: String
        let confirmedMode: FanPolicy.Mode?
        let serviceEnabled: Bool
        let expectedFanControlRevision: Int
        let serviceFanControlRevision: Int?
        let active: Bool
        let restorationPending: Bool
        let requestedPolicy: FanPolicy
        let configuredPolicy: FanPolicy
        let fans: [FanReading]
        let stopCause: HardwareReason?
        let currentError: HardwareReason?
        let primaryFailure: FanFailure?
        let recoveryFailure: FanFailure?
        let localReadings: LocalReadings
    }

    func diagnosticData() async -> Data? {
        let readings = await diagnosticReadings(), keys = await diagnosticKeys()
        // SPEC: diagnostics omit maintenance IDs, user identifiers, paths and environment data.
        let local = LocalReadings(fans: readings.fans, temperature: readings.temperature,
            availability: readings.fanAvailability, keys: Array(keys.filter(\.valid).prefix(FanKeyReading.keys.count)))
        let value = Diagnostic(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            model: FanDevice.modelIdentifier, macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            confirmedMode: confirmedFanMode, serviceEnabled: serviceEnabled,
            expectedFanControlRevision: FanControlSupport.revision, serviceFanControlRevision: snapshot.fanControlRevision,
            active: snapshot.active, restorationPending: snapshot.restorationPending,
            requestedPolicy: lastFanRequest ?? snapshot.policy, configuredPolicy: snapshot.policy,
            fans: snapshot.fans, stopCause: snapshot.stopCause, currentError: failure ?? snapshot.reason,
            primaryFailure: snapshot.fanFailure, recoveryFailure: snapshot.fanRecoveryFailure, localReadings: local)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(value)
    }

    func copyErrorDetails() async {
        guard let data = await diagnosticData(), let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
