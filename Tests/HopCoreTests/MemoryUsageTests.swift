import XCTest
@testable import HopCore

/// "Memory Used" matches Activity Monitor by subtracting Cached Files and the
/// genuinely free pages from Physical. Two counters lie in wait here: Mach's
/// `free_count` already contains the speculative pages, and purgeable memory is
/// App Memory rather than cache. Deducting either one again pulls the figure
/// below the system's, which is exactly what users notice.
final class MemoryUsageTests: XCTestCase {

    // A live sample taken beside an Activity Monitor reading of 20.98 GB Used
    // on a 24 GiB machine with 16 KiB pages (2026-07-27).
    private let page: UInt64 = 16384
    private let physical: UInt64 = 25_769_803_776
    private let free: UInt64 = 9409             // free_count, speculative included
    private let speculative: UInt64 = 3178
    private let fileBacked: UInt64 = 192_876    // external_page_count
    private let anonymous: UInt64 = 491_674     // internal_page_count (incl. purgeable)
    private let wired: UInt64 = 186_915
    private let compressor: UInt64 = 640_733
    private let purgeable: UInt64 = 3_535

    private var used: Double {
        MemoryUsage.usedBytes(
            physicalBytes: physical, pageSize: page,
            free: free, speculative: speculative, fileBacked: fileBacked)
    }

    func testUsedMatchesActivityMonitor() {
        // 20.962 GiB against Activity Monitor's displayed 20.98 — the residual is
        // the second or so between the two samples, not a term in the formula.
        XCTAssertEqual(used, 22_507_634_688, accuracy: 1)
        XCTAssertEqual(used / 1_073_741_824, 20.98, accuracy: 0.05)
    }

    func testSpeculativePagesAreDeductedOnce() {
        // free_count already covers them: passing the pair must equal passing the
        // difference with no speculative term at all.
        let asDifference = MemoryUsage.usedBytes(
            physicalBytes: physical, pageSize: page,
            free: free - speculative, speculative: 0, fileBacked: fileBacked)
        XCTAssertEqual(used, asDifference, accuracy: 1)
    }

    func testPurgeableStaysInsideUsed() {
        // Activity Monitor counts purgeable pages in App Memory, so growing them
        // must not move "Used" at all. The old formula subtracted them, which is
        // how the figure drifted a gigabyte low on a busy machine.
        let quiet = MemoryUsage.usedBytes(
            physicalBytes: physical, pageSize: page,
            free: free, speculative: speculative, fileBacked: fileBacked)
        XCTAssertEqual(quiet, used, accuracy: 1)
        XCTAssertGreaterThan(used, Double((anonymous - purgeable + wired + compressor) * page))
    }

    /// Subtraction sits ABOVE the additive App-Memory-plus-wired-plus-compressed
    /// sum by exactly the reserved slice — the GPU/firmware carve-out that
    /// host_statistics64 files in no queue.
    func testSubtractionExceedsAdditiveByTheReservedTerm() {
        let additive = Double((anonymous - purgeable + wired + compressor) * page)
        let reserved = MemoryUsage.reservedPages(
            physicalPages: physical / page,
            free: free, fileBacked: fileBacked,
            anonymous: anonymous, wired: wired, compressor: compressor)

        XCTAssertEqual(reserved, 51_257)                             // ~0.78 GB reserved
        // Identity: the two differ by the reserved slice plus the two terms the
        // additive sum leaves out on purpose — speculative and purgeable pages.
        let missing = Double(reserved &+ Int64(speculative) &+ Int64(purgeable)) * Double(page)
        XCTAssertEqual(used, additive + missing, accuracy: 1)
        XCTAssertEqual(used - additive, 949_780_480, accuracy: 1)    // ~0.88 GB
    }

    func testNoReservedSliceMakesSubtractionEqualAdditive() {
        // A synthetic machine where every physical page is categorised
        // (reserved == 0) and nothing is purgeable: the two agree exactly.
        let phys: UInt64 = 100
        let f: UInt64 = 10, spec: UInt64 = 0, ext: UInt64 = 20
        let anon: UInt64 = 50, wire: UInt64 = 15, comp: UInt64 = 5
        // f + ext + anon + wire + comp = 100 = phys → reserved 0.
        let reserved = MemoryUsage.reservedPages(
            physicalPages: phys, free: f, fileBacked: ext,
            anonymous: anon, wired: wire, compressor: comp)
        XCTAssertEqual(reserved, 0)

        let value = MemoryUsage.usedBytes(
            physicalBytes: phys * page, pageSize: page,
            free: f, speculative: spec, fileBacked: ext)
        XCTAssertEqual(value, Double((anon + wire + comp) * page), accuracy: 1)
    }

    func testCacheAbovePhysicalClampsToZero() {
        // Guard the underflow branch: absurd cache counts never yield a negative.
        let value = MemoryUsage.usedBytes(
            physicalBytes: page, pageSize: page,
            free: 100, speculative: 0, fileBacked: 0)
        XCTAssertEqual(value, 0)
    }

    func testSpeculativeAboveFreeClampsInsteadOfWrapping() {
        // The two counters are read a hair apart; a sample can catch speculative
        // above free without the arithmetic wrapping around zero.
        let value = MemoryUsage.usedBytes(
            physicalBytes: physical, pageSize: page,
            free: 10, speculative: 4_000, fileBacked: fileBacked)
        XCTAssertEqual(value, Double(physical - fileBacked * page), accuracy: 1)
    }
}
