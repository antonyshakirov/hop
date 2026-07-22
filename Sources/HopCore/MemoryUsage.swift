/// Activity Monitor's "Memory Used", derived from `vm_statistics64` page counts.
///
/// Activity Monitor splits the whole Physical Memory bar into three slices —
/// Memory Used, Cached Files, and free — so its "Used" figure is
/// `Physical − Cached Files − free`.
///
/// The earlier additive sum (App Memory + wired + compressed, where App Memory =
/// anonymous − purgeable) dropped one slice: the kernel/hardware-reserved pages
/// that `host_statistics64` reports in NO page queue. On Apple Silicon that is
/// the GPU/firmware carve-out of unified memory — roughly a gigabyte — which
/// Activity Monitor still attributes to Memory Used. So the additive figure ran
/// about 1 GB below the system's.
///
/// Subtracting only the reclaimable cache (file-backed + purgeable) and the free
/// pages (free + speculative) from Physical recovers that slice: whatever the
/// kernel leaves uncategorised stays inside `Physical`, and therefore inside
/// "Used", exactly as Activity Monitor keeps it.
public enum MemoryUsage {

    /// "Memory Used" in bytes, matching Activity Monitor.
    ///
    /// - Parameters:
    ///   - physicalBytes: `hw.memsize` — the full Physical Memory bar.
    ///   - pageSize: VM page size in bytes.
    ///   - free: `free_count` — genuinely free pages.
    ///   - speculative: `speculative_count` — prefetched, not yet touched; free.
    ///   - fileBacked: `external_page_count` — reclaimable file cache.
    ///   - purgeable: `purgeable_count` — reclaimable anonymous pages.
    public static func usedBytes(
        physicalBytes: UInt64,
        pageSize: UInt64,
        free: UInt64,
        speculative: UInt64,
        fileBacked: UInt64,
        purgeable: UInt64
    ) -> Double {
        let reclaimableBytes = (free &+ speculative &+ fileBacked &+ purgeable) &* pageSize
        // A momentary sampling skew (the counts are read a hair apart from
        // hw.memsize) could push the cache above Physical; never report negative.
        return physicalBytes > reclaimableBytes ? Double(physicalBytes &- reclaimableBytes) : 0
    }

    /// The kernel/hardware-reserved pages the additive "App Memory + wired +
    /// compressed" sum omits: every page in `Physical` that `host_statistics64`
    /// files in no queue. This is the term that made the additive figure ~1 GB
    /// low. Exposed for tests and diagnostics — `usedBytes` already folds it in.
    ///
    /// `anonymous` (`internal_page_count`) already includes `purgeable`, so it is
    /// not added again here.
    public static func reservedPages(
        physicalPages: UInt64,
        free: UInt64,
        speculative: UInt64,
        fileBacked: UInt64,
        anonymous: UInt64,
        wired: UInt64,
        compressor: UInt64
    ) -> Int64 {
        let accounted = free &+ speculative &+ fileBacked &+ anonymous &+ wired &+ compressor
        return Int64(bitPattern: physicalPages) &- Int64(bitPattern: accounted)
    }
}
