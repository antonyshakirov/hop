import XCTest
@testable import HopCore

final class NetworkSightingsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func testRepeatedConnectionsCountOnce() {
        var log = NetworkSightings()
        log.record(app: "a", path: nil, host: "x.com", address: "1.1.1.1", port: "443", verdict: .allow, at: t0)
        log.record(app: "a", path: "/p", host: "x.com", address: "1.1.1.2", port: "443", verdict: .deny,
                   at: t0.addingTimeInterval(5))
        XCTAssertEqual(log.all.count, 1)
        XCTAssertEqual(log.all[0].count, 2)
        XCTAssertEqual(log.all[0].verdict, .deny)
        XCTAssertEqual(log.all[0].path, "/p")
    }

    func testAnAddressWithoutANameIsItsOwnDestination() {
        var log = NetworkSightings()
        log.record(app: "a", path: nil, host: nil, address: "1.1.1.1", port: "53", verdict: .allow, at: t0)
        log.record(app: "a", path: nil, host: nil, address: "8.8.8.8", port: "53", verdict: .allow, at: t0)
        XCTAssertEqual(Set(log.all.map(\.destination)), ["1.1.1.1", "8.8.8.8"])
    }

    func testTheLogForgetsTheOldestPastItsCapacity() {
        var log = NetworkSightings()
        for i in 0...NetworkSightings.capacity {
            log.record(app: "a", path: nil, host: "h\(i).com", address: "1.1.1.1", port: "443", verdict: .allow,
                       at: t0.addingTimeInterval(Double(i)))
        }
        XCTAssertLessThanOrEqual(log.all.count, NetworkSightings.capacity)
        XCTAssertNil(log.byKey["a\u{1F}h0.com"])
        XCTAssertNotNil(log.byKey["a\u{1F}h\(NetworkSightings.capacity).com"])
    }

    func testProgramsGroupTheirDestinationsAndShowRulesAhead() {
        let sightings = [
            NetworkSighting(app: "a", path: "/a", host: "x.com", address: "1", port: "443", verdict: .allow, last: t0),
            NetworkSighting(app: "b", path: "/b", host: "y.com", address: "2", port: "443", verdict: .allow,
                            last: t0.addingTimeInterval(10)),
            NetworkSighting(app: "a", path: "/a", host: "z.com", address: "3", port: "443", verdict: .allow,
                            last: t0.addingTimeInterval(20)),
        ]
        let rules = [NetworkRule(app: "b", action: .deny), NetworkRule(app: "c", host: "lic.com", action: .deny)]
        let programs = NetworkProgram.group(sightings, rules: rules)
        XCTAssertEqual(programs.map(\.app), ["a", "b", "c"])
        XCTAssertEqual(programs[0].destinations.map(\.destination), ["z.com", "x.com"])
        XCTAssertEqual(programs.map(\.blocked), [false, true, false])
    }

    func testSightingsSurviveTheTripFromTheFilter() {
        let list = [NetworkSighting(app: "a", path: nil, host: nil, address: "1", port: "1", verdict: .deny, last: t0)]
        XCTAssertEqual(NetworkSightings.decode(NetworkSightings.encode(list)), list)
    }
}
