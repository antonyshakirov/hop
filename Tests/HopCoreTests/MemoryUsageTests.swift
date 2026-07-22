import XCTest
@testable import HopCore

/// "Memory Used" matches Activity Monitor by subtracting reclaimable cache and
/// free pages from Physical, so the kernel/hardware-reserved pages that
/// host_statistics64 files in no queue stay counted — the ~1 GB the old additive
/// "App Memory + wired + compressed" sum dropped.
final class MemoryUsageTests: XCTestCase {

    // A synthetic 24 GiB machine, 16 KiB pages, mirroring a real vm_stat sample.
    private let page: UInt64 = 16384
    private let physical: UInt64 = 24 * 1024 * 1024 * 1024   // 25_769_803_776

    // vm_stat page counts from a live probe.
    private let free: UInt64 = 14280
    private let speculative: UInt64 = 1556
    private let fileBacked: UInt64 = 308624     // external_page_count
    private let anonymous: UInt64 = 640603      // internal_page_count (incl. purgeable)
    private let wired: UInt64 = 148931
    private let compressor: UInt64 = 406082
    private let purgeable: UInt64 = 7302

    func testUsedIsPhysicalMinusReclaimableAndFree() {
        let used = MemoryUsage.usedBytes(
            physicalBytes: physical, pageSize: page,
            free: free, speculative: speculative,
            fileBacked: fileBacked, purgeable: purgeable)
        let expected = Double(physical - (free + speculative + fileBacked + purgeable) * page)
        XCTAssertEqual(used, expected, accuracy: 1)
        // Ground-truth number from the live probe: ~20.33 GB (18.94 GiB).
        XCTAssertEqual(used, 20_334_215_168, accuracy: 1)
    }

    /// The whole point: subtraction recovers the reserved slice, so it must sit
    /// ABOVE the additive App-Memory-plus-wired-plus-compressed sum by exactly
    /// the reserved term — here the ~0.87 GB the old formula lost.
    func testSubtractionExceedsAdditiveByTheReservedTerm() {
        let used = MemoryUsage.usedBytes(
            physicalBytes: physical, pageSize: page,
            free: free, speculative: speculative,
            fileBacked: fileBacked, purgeable: purgeable)
        let additive = Double((anonymous - purgeable + wired + compressor) * page)
        let reserved = MemoryUsage.reservedPages(
            physicalPages: physical / page,
            free: free, speculative: speculative, fileBacked: fileBacked,
            anonymous: anonymous, wired: wired, compressor: compressor)

        XCTAssertEqual(reserved, 52788)                              // ~0.87 GB of reserved pages
        XCTAssertGreaterThan(used, additive)
        // Identity: subtraction == additive + reserved.
        XCTAssertEqual(used, additive + Double(reserved) * Double(page), accuracy: 1)
        // The gap the fix closes is ~0.865 GB.
        XCTAssertEqual(used - additive, 864_878_592, accuracy: 1)
    }

    func testNoReservedSliceMakesSubtractionEqualAdditive() {
        // A synthetic machine where every physical page is categorised
        // (reserved == 0): subtraction and the additive sum must coincide.
        let phys: UInt64 = 100
        let f: UInt64 = 10, spec: UInt64 = 0, ext: UInt64 = 20
        let anon: UInt64 = 50, wire: UInt64 = 15, comp: UInt64 = 5, purg: UInt64 = 8
        // f + ext + anon + wire + comp = 10 + 20 + 50 + 15 + 5 = 100 = phys → reserved 0.
        let reserved = MemoryUsage.reservedPages(
            physicalPages: phys, free: f, speculative: spec, fileBacked: ext,
            anonymous: anon, wired: wire, compressor: comp)
        XCTAssertEqual(reserved, 0)

        let used = MemoryUsage.usedBytes(
            physicalBytes: phys * page, pageSize: page,
            free: f, speculative: spec, fileBacked: ext, purgeable: purg)
        let additive = Double((anon - purg + wire + comp) * page)
        XCTAssertEqual(used, additive, accuracy: 1)
    }

    func testCacheAbovePhysicalClampsToZero() {
        // Guard the underflow branch: absurd cache counts never yield a negative.
        let used = MemoryUsage.usedBytes(
            physicalBytes: page, pageSize: page,
            free: 100, speculative: 0, fileBacked: 0, purgeable: 0)
        XCTAssertEqual(used, 0)
    }
}
