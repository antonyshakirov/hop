import CoreGraphics
import Foundation
import IOKit

/// Blanks the built-in panel while the lid is closed in lid mode.
///
/// `pmset disablesleep 1` keeps the whole machine powered, so macOS never
/// turns the built-in backlight off under a closed lid. While lid mode is
/// active we watch the clamshell state and drop the built-in display's
/// brightness to zero when the lid closes, restoring it when it opens.
/// External displays are never touched. All writes are synchronous so the
/// restore also works from the app-termination path.
@MainActor
final class LidDimmer {
    /// Brightness to restore after a crash while dimmed (cleared on restore).
    private static let savedBrightnessKey = "lidDimSavedBrightness"

    private var poll: Timer?
    private var dimmed = false

    /// If a previous run crashed while the panel was dimmed, bring it back.
    static func restorePendingAtLaunch() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: savedBrightnessKey) != nil else { return }
        let saved = defaults.float(forKey: savedBrightnessKey)
        defaults.removeObject(forKey: savedBrightnessKey)
        if let id = builtinDisplayID(), let services = displayServices {
            _ = services.set(id, max(0.05, saved))
        }
    }

    func start() {
        guard poll == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        poll = t
        tick()
    }

    func stop() {
        poll?.invalidate()
        poll = nil
        if dimmed { restore() }
    }

    private func tick() {
        let closed = Self.clamshellClosed()
        if closed && !dimmed {
            dim()
        } else if !closed && dimmed {
            restore()
        }
    }

    private func dim() {
        guard let id = Self.builtinDisplayID(), let services = Self.displayServices else { return }
        var current: Float = 0
        guard services.get(id, &current) == 0, current > 0 else { return }
        dimmed = true
        UserDefaults.standard.set(current, forKey: Self.savedBrightnessKey)
        _ = services.set(id, 0)
    }

    private func restore() {
        dimmed = false
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.savedBrightnessKey) != nil else { return }
        let saved = defaults.float(forKey: Self.savedBrightnessKey)
        defaults.removeObject(forKey: Self.savedBrightnessKey)
        guard let id = Self.builtinDisplayID(), let services = Self.displayServices else { return }
        _ = services.set(id, max(0.05, saved))
    }

    // MARK: - System plumbing

    private static func clamshellClosed() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPMrootDomain")
        )
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Bool else { return false }
        return value
    }

    private static func builtinDisplayID() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    /// DisplayServices is the same private framework the brightness keys use;
    /// it is the only way to drive the built-in backlight on Apple silicon.
    private static let displayServices: (get: GetBrightness, set: SetBrightness)? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        ) else { return nil }
        guard let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
              let setSymbol = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return (
            unsafeBitCast(getSymbol, to: GetBrightness.self),
            unsafeBitCast(setSymbol, to: SetBrightness.self)
        )
    }()
}
