import Foundation

/// How hard the machine is working to hold its memory — the verdict behind the
/// colour of the monitor's memory row.
///
/// TWO signals, and the worse one wins, because each is blind to what the other
/// sees:
///
/// - **macOS's own pressure level** (`kern.memorystatus_vm_pressure_level`)
///   answers "am I struggling to hand out pages right now". It is the honest
///   answer to that question and nothing else. Pages that were pushed to disk
///   and have stayed cold since cost the system nothing, so it keeps reporting
///   normal while a great deal of memory sits in swap — measured on a 24 GB
///   machine holding 9.4 GB of swap, the level was still 1 (Anton, 2026-07-28).
/// - **Swap measured against physical RAM** answers "how much of my working set
///   is living on disk". That is a fact about the machine rather than a guess at
///   how it feels, and it is the part the user can act on: close something.
///
/// Swap is compared to RAM and NOT to the size of the swap file. macOS grows
/// that file on demand, so "92% of the file" becomes "46%" the moment it grows,
/// with nothing about the machine having changed. RAM is fixed, and it is what
/// the number means something against.
///
/// The old rule this replaces coloured on `(used + swap) ÷ RAM`, yellow at 110%.
/// Adding a figure that already counts compressed memory to a pool that lives on
/// disk, then comparing the sum to the size of RAM, produces a number with no
/// physical meaning — a "normal" threshold above 100% is the tell.
public enum MemoryStrain {

    /// Ordered so that combining two readings is just `max`.
    public enum Level: Int, Comparable, Sendable {
        /// Nothing to go on: the counters were unavailable.
        case unknown = 0
        case normal = 1
        case warning = 2
        case critical = 3

        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    /// macOS's verdict as reported by `kern.memorystatus_vm_pressure_level`.
    /// The kernel numbers these 1, 2 and 4 — 3 is not a level.
    public static func fromPressure(_ level: Int?) -> Level {
        switch level {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return .unknown
        }
    }

    /// Swap as a share of physical RAM, against the two thresholds.
    /// `yellowPercent` and `redPercent` are shares of RAM, so 25 means "a
    /// quarter of this machine's memory is currently on disk".
    public static func fromSwap(
        swapBytes: Double?,
        physicalBytes: Double?,
        yellowPercent: Int,
        redPercent: Int
    ) -> Level {
        guard let swapBytes, let physicalBytes, physicalBytes > 0 else { return .unknown }
        let share = swapBytes / physicalBytes * 100
        // red first: a machine can be past both, and the worse one is the answer
        if share >= Double(redPercent) { return .critical }
        if share >= Double(yellowPercent) { return .warning }
        return .normal
    }

    /// The verdict the row shows: whichever signal is more alarmed.
    public static func level(
        pressure: Int?,
        swapBytes: Double?,
        physicalBytes: Double?,
        yellowPercent: Int,
        redPercent: Int
    ) -> Level {
        max(fromPressure(pressure),
            fromSwap(swapBytes: swapBytes, physicalBytes: physicalBytes,
                     yellowPercent: yellowPercent, redPercent: redPercent))
    }
}
