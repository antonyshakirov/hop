/// Activity Monitor's "Memory Used", derived from `vm_statistics64` page counts.
///
/// Activity Monitor splits the whole Physical Memory bar into three slices —
/// Memory Used, Cached Files, and free — so its "Used" figure is
/// `Physical − Cached Files − free`. Measured against a live Activity Monitor
/// reading (2026-07-27, 24 GiB machine, "Used" 20.98 GB) the two subtracted
/// terms are exactly:
///
/// - **Cached Files** = `external_page_count` and nothing else. Purgeable pages
///   are NOT cache here: Activity Monitor counts them inside App Memory, and
///   therefore inside "Used". Subtracting them ran the figure low by however
///   much purgeable memory the machine happened to hold — a gigabyte at times.
/// - **free** = `free_count − speculative_count`. Mach's `free_count` ALREADY
///   INCLUDES the speculative pages (this is why `vm_stat` prints the two apart:
///   its "Pages free" line is the subtraction, not the raw field). Subtracting
///   `speculative_count` a second time on top of the raw `free_count` took the
///   figure further down for nothing.
///
/// The earlier additive sum (App Memory + wired + compressed, where App Memory =
/// anonymous − purgeable) drops a different slice: the kernel/hardware-reserved
/// pages that `host_statistics64` reports in NO page queue. On Apple Silicon
/// that is the GPU/firmware carve-out of unified memory — measured at 0.78 GB
/// on the same machine — which Activity Monitor still attributes to Memory
/// Used. Subtraction keeps that slice inside the figure by construction.
public enum MemoryUsage {

    /// "Memory Used" in bytes, matching Activity Monitor.
    ///
    /// - Parameters:
    ///   - physicalBytes: `hw.memsize` — the full Physical Memory bar.
    ///   - pageSize: VM page size in bytes.
    ///   - free: `free_count` — RAW, speculative pages included.
    ///   - speculative: `speculative_count` — prefetched pages, already counted
    ///     inside `free`; removed here so they are not deducted twice.
    ///   - fileBacked: `external_page_count` — Activity Monitor's Cached Files.
    public static func usedBytes(
        physicalBytes: UInt64,
        pageSize: UInt64,
        free: UInt64,
        speculative: UInt64,
        fileBacked: UInt64
    ) -> Double {
        // A sample can catch speculative above free between two counter updates;
        // clamping keeps the arithmetic from wrapping around zero.
        let genuinelyFree = free > speculative ? free &- speculative : 0
        let notUsedBytes = (genuinelyFree &+ fileBacked) &* pageSize
        // A momentary sampling skew (the counts are read a hair apart from
        // hw.memsize) could push the cache above Physical; never report negative.
        return physicalBytes > notUsedBytes ? Double(physicalBytes &- notUsedBytes) : 0
    }

    /// The kernel/hardware-reserved pages the additive "App Memory + wired +
    /// compressed" sum omits: every page in `Physical` that `host_statistics64`
    /// files in no queue. This is the term that makes the additive figure run
    /// low. Exposed for tests and diagnostics — `usedBytes` already folds it in.
    ///
    /// `free` is the raw `free_count`, which already covers the speculative
    /// pages — they are not added a second time.
    ///
    /// `anonymous` (`internal_page_count`) already includes `purgeable`, so it is
    /// not added again here either.
    public static func reservedPages(
        physicalPages: UInt64,
        free: UInt64,
        fileBacked: UInt64,
        anonymous: UInt64,
        wired: UInt64,
        compressor: UInt64
    ) -> Int64 {
        let accounted = free &+ fileBacked &+ anonymous &+ wired &+ compressor
        return Int64(bitPattern: physicalPages) &- Int64(bitPattern: accounted)
    }
}
