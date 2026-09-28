import XCTest
@testable import HopCore

final class NetworkRuleFileTests: XCTestCase {
    private func flow(_ host: String, app: String = "com.a") -> NetworkFlow {
        NetworkFlow(apps: [app], hostname: host, address: "1.2.3.4")
    }

    func testAnAddressBlockedForEveryProgram() {
        let rules = [NetworkRule(app: NetworkRule.anyProgram, host: "tracker.com", action: .deny)]
        XCTAssertEqual(NetworkRules.verdict(for: flow("tracker.com"), rules: rules), .deny)
        XCTAssertEqual(NetworkRules.verdict(for: flow("cdn.tracker.com", app: "com.b"), rules: rules), .deny)
        XCTAssertEqual(NetworkRules.verdict(for: flow("example.com"), rules: rules), .allow)
    }

    func testAProgramsOwnRuleBeatsTheOneForEveryProgram() {
        let rules = [NetworkRule(app: NetworkRule.anyProgram, host: "tracker.com", action: .deny),
                     NetworkRule(app: "com.a", host: "tracker.com", action: .allow)]
        let resolved = ["tracker.com": Set(["1.2.3.4"])]
        XCTAssertEqual(NetworkRules.verdict(for: flow("tracker.com"), rules: rules, addresses: resolved), .allow)
        XCTAssertEqual(NetworkRules.verdict(for: flow("tracker.com", app: "com.b"), rules: rules), .deny)
    }

    func testEveryProgramCannotBeCutOffWhole() {
        let rules = [NetworkRule(app: NetworkRule.anyProgram, action: .deny)]
        XCTAssertEqual(NetworkRules.verdict(for: flow("example.com"), rules: rules), .allow)
        XCTAssertEqual(NetworkRuleFile.parse("*"), [])
    }

    func testAPlainListBlocksEachAddressForEveryProgram() {
        let text = "# trackers\ntracker.com\n\n  ads.example.net  # inline\n"
        XCTAssertEqual(NetworkRuleFile.parse(text), [
            NetworkRule(app: NetworkRule.anyProgram, host: "tracker.com", action: .deny),
            NetworkRule(app: NetworkRule.anyProgram, host: "ads.example.net", action: .deny),
        ])
    }

    func testAHostsFileIsReadAsABlockList() {
        let text = "127.0.0.1 localhost\n0.0.0.0 tracker.com\n0.0.0.0 ads.example.net other.example.net\n::1 localhost"
        XCTAssertEqual(NetworkRuleFile.parse(text).map(\.host), ["tracker.com", "ads.example.net", "other.example.net"])
    }

    func testLinesCanNameTheProgramAndTheAction() {
        let text = """
        com.adobe.acc license.adobe.com
        com.apple.curl example.com allow
        com.example.app *
        block telemetry.net
        allow updates.example.com
        """
        XCTAssertEqual(NetworkRuleFile.parse(text), [
            NetworkRule(app: "com.adobe.acc", host: "license.adobe.com", action: .deny),
            NetworkRule(app: "com.apple.curl", host: "example.com", action: .allow),
            NetworkRule(app: "com.example.app", action: .deny),
            NetworkRule(app: NetworkRule.anyProgram, host: "telemetry.net", action: .deny),
            NetworkRule(app: NetworkRule.anyProgram, host: "updates.example.com", action: .allow),
        ])
    }

    func testTheSavedFileReadsBackAsTheSameRules() {
        let rules = [NetworkRule(app: "com.a", action: .deny),
                     NetworkRule(app: "com.a", host: "x.com", action: .allow),
                     NetworkRule(app: NetworkRule.anyProgram, host: "t.com", action: .deny)]
        XCTAssertEqual(NetworkRuleFile.parse(NetworkRuleFile.text(rules)), rules)
    }

    func testMergingKeepsOneRulePerProgramAndAddress() {
        let old = [NetworkRule(app: "com.a", host: "x.com", action: .allow)]
        let new = [NetworkRule(app: "com.a", host: "x.com", action: .deny), NetworkRule(app: "com.b", action: .deny)]
        XCTAssertEqual(NetworkRuleFile.merge(old, new), new)
    }
}

final class NetworkRuleSafetyTests: XCTestCase {
    func testABareAddressLineBlocksThatAddress() {
        XCTAssertEqual(NetworkRuleFile.parse("1.2.3.4\ntracker.com\n"), [
            NetworkRule(app: NetworkRule.anyProgram, host: "1.2.3.4", action: .deny),
            NetworkRule(app: NetworkRule.anyProgram, host: "tracker.com", action: .deny),
        ])
    }

    func testAHostsFileHeaderDoesNotBreakTheLocalNetwork() {
        let header = """
        127.0.0.1 localhost
        127.0.0.1 localhost.localdomain
        127.0.0.1 local
        255.255.255.255 broadcasthost
        ::1 localhost
        ::1 ip6-localhost ip6-loopback
        fe80::1%lo0 localhost
        ff00::0 ip6-localnet
        0.0.0.0 0.0.0.0
        0.0.0.0 ads.example.com
        com
        """
        XCTAssertEqual(NetworkRuleFile.parse(header).map(\.host), ["ads.example.com"])
    }

    func testAnAllowByNameCountsOnlyForAnAddressTheNameReallyHas() {
        let rules = [NetworkRule(app: "evil", action: .deny),
                     NetworkRule(app: "evil", host: "github.com", action: .allow)]
        let spoofed = NetworkFlow(apps: ["evil"], hostname: "github.com", address: "6.6.6.6")
        let honest = NetworkFlow(apps: ["evil"], hostname: "github.com", address: "140.82.121.4")
        let resolved = ["github.com": Set(["140.82.121.4"])]
        XCTAssertEqual(NetworkRules.verdict(for: spoofed, rules: rules, addresses: resolved), .deny)
        XCTAssertEqual(NetworkRules.verdict(for: honest, rules: rules, addresses: resolved), .allow)
    }

    func testAnUnconfirmedNameAsksToBeLookedUp() {
        let index = NetworkRuleIndex([NetworkRule(app: "a", action: .deny),
                                      NetworkRule(app: "a", host: "example.com", action: .allow)])
        let flow = NetworkFlow(apps: ["a"], hostname: "api.example.com", address: "1.1.1.1")
        let result = index.ruled(flow, resolved: [:])
        XCTAssertEqual(result.action, .deny)
        XCTAssertEqual(result.lookUp, "api.example.com")
        let later = index.ruled(flow, resolved: ["api.example.com": ["1.1.1.1"]])
        XCTAssertEqual(later.action, .allow)
        XCTAssertNil(later.lookUp)
    }

    func testABlockByNameNeedsNoConfirmation() {
        let rules = [NetworkRule(app: "a", host: "license.example.com", action: .deny)]
        let flow = NetworkFlow(apps: ["a"], hostname: "license.example.com", address: "9.9.9.9")
        XCTAssertEqual(NetworkRules.verdict(for: flow, rules: rules), .deny)
    }

    func testOnlyProgramRulesAndAllowsAreResolvedAndNotTooMany() {
        var rules = (0..<500).map { NetworkRule(app: NetworkRule.anyProgram, host: "ad\($0).com", action: .deny) }
        rules += (0..<300).map { NetworkRule(app: "a", host: "h\($0).com", action: .deny) }
        rules.append(NetworkRule(app: NetworkRule.anyProgram, host: "ok.com", action: .allow))
        let hosts = NetworkRules.hostsToResolve(rules)
        XCTAssertEqual(hosts.count, NetworkRules.resolveLimit)
        XCTAssertFalse(hosts.contains("ad1.com"))
        XCTAssertTrue(hosts.contains("ok.com"))
    }

    func testAHundredThousandRulesStillDecideQuickly() {
        let rules = (0..<100_000).map { NetworkRule(app: NetworkRule.anyProgram, host: "ad\($0).example.com", action: .deny) }
        let index = NetworkRuleIndex(rules)
        let flow = NetworkFlow(apps: ["a"], hostname: "cdn.ad99999.example.com", address: "1.1.1.1")
        let started = Date()
        for _ in 0..<1000 { _ = index.ruled(flow, resolved: [:]) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        XCTAssertEqual(index.ruled(flow, resolved: [:]).action, .deny)
    }

    func testAJSONFileMeetsTheSameNameRules() {
        let json = #"[{"app":"*","host":"com","action":"deny"},{"app":"*","host":"local","action":"deny"},"#
            + #"{"app":"*","action":"deny"},{"app":"a","host":"x.com","action":"deny"}]"#
        XCTAssertEqual(NetworkRuleFile.parse(json), [NetworkRule(app: "a", host: "x.com", action: .deny)])
    }
}
