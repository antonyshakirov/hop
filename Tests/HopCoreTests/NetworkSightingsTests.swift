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

final class NetworkProgramOrderTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func program(_ app: String, _ minutes: Double?) -> NetworkProgram {
        NetworkProgram(app: app, path: nil, destinations: [], last: minutes.map { t0.addingTimeInterval($0 * 60) },
                       blocked: false)
    }

    func testTheFirstOrderIsNewestFirst() {
        XCTAssertEqual(NetworkProgramOrder.update([], with: [program("a", 1), program("b", 5), program("c", nil)]),
                       ["b", "a", "c"])
    }

    func testAProgramKeepsItsPlaceWhateverHappensToIt() {
        let order = ["a", "b", "c"]
        let later = [program("c", 90), program("b", nil), program("a", 10)]
        XCTAssertEqual(NetworkProgramOrder.update(order, with: later), ["a", "b", "c"])
    }

    func testNewProgramsComeAfterTheOnesAlreadyShown() {
        XCTAssertEqual(NetworkProgramOrder.update(["a"], with: [program("a", 1), program("d", 3), program("e", 9)]),
                       ["a", "e", "d"])
    }

    func testARestartedFilterDoesNotEmptyTheList() {
        let before = NetworkSighting(app: "a", path: "/p", host: "x.com", address: "1", port: "443",
                                     verdict: .allow, count: 40, last: t0)
        let after = NetworkSighting(app: "a", path: nil, host: "x.com", address: "2", port: "443",
                                    verdict: .deny, count: 1, last: t0.addingTimeInterval(60))
        let merged = NetworkProgramOrder.merge(["a\u{1F}x.com": before], [after])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged["a\u{1F}x.com"]?.count, 40)
        XCTAssertEqual(merged["a\u{1F}x.com"]?.verdict, .deny)
        XCTAssertEqual(merged["a\u{1F}x.com"]?.path, "/p")
        XCTAssertEqual(NetworkProgramOrder.merge(merged, []).count, 1)
    }
}
