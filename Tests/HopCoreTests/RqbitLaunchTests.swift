import XCTest
@testable import HopCore

final class RqbitLaunchTests: XCTestCase {
    func testFullArgsInCorrectOrder() {
        let a = RqbitLaunch.arguments(port: 1234, downloadFolder: "/out", persistenceDir: "/p",
                                      rateDownBps: 2_000_000, rateUpBps: 500_000)
        XCTAssertEqual(a, ["--http-api-listen-addr", "127.0.0.1:1234",
                           "--ratelimit-download", "2000000",
                           "--ratelimit-upload", "500000",
                           "server", "start", "--persistence-location", "/p", "/out"])
    }
    func testNoRateLimitsWhenNil() {
        let a = RqbitLaunch.arguments(port: 3030, downloadFolder: "/out", persistenceDir: "/p",
                                      rateDownBps: nil, rateUpBps: nil)
        XCTAssertEqual(a, ["--http-api-listen-addr", "127.0.0.1:3030",
                           "server", "start", "--persistence-location", "/p", "/out"])
    }
    func testGlobalFlagsBeforeServerStartAndPersistenceAfter() {
        let a = RqbitLaunch.arguments(port: 1, downloadFolder: "/o", persistenceDir: "/p",
                                      rateDownBps: 10, rateUpBps: nil)
        let serverIdx = a.firstIndex(of: "server")!
        XCTAssertLessThan(a.firstIndex(of: "--http-api-listen-addr")!, serverIdx)
        XCTAssertLessThan(a.firstIndex(of: "--ratelimit-download")!, serverIdx)
        XCTAssertGreaterThan(a.firstIndex(of: "--persistence-location")!, serverIdx)
        XCTAssertEqual(a.last, "/o") // download folder is the trailing positional
    }
}
