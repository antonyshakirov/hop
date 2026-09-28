import XCTest
@testable import HopCore

final class NetworkRulesTests: XCTestCase {
    private let curl = "com.apple.curl"

    private func flow(_ host: String?, _ address: String = "93.184.216.34", app: String? = nil) -> NetworkFlow {
        NetworkFlow(apps: [app ?? curl], hostname: host, address: address)
    }

    func testNoRuleLetsTheConnectionThrough() {
        XCTAssertEqual(NetworkRules.verdict(for: flow("example.com"), rules: []), .allow)
    }

    func testAProgramCanBeCutOffEntirely() {
        let rules = [NetworkRule(app: curl, action: .deny)]
        XCTAssertEqual(NetworkRules.verdict(for: flow("example.com"), rules: rules), .deny)
        XCTAssertEqual(NetworkRules.verdict(for: flow(nil, "1.1.1.1"), rules: rules), .deny)
        XCTAssertEqual(NetworkRules.verdict(for: flow("example.com", app: "com.other"), rules: rules), .allow)
    }

    func testADestinationRuleBeatsTheWholeProgram() {
        let rules = [NetworkRule(app: curl, action: .deny),
                     NetworkRule(app: curl, host: "updates.example.com", action: .allow)]
        XCTAssertEqual(NetworkRules.verdict(for: flow("updates.example.com"), rules: rules), .allow)
        XCTAssertEqual(NetworkRules.verdict(for: flow("example.com"), rules: rules), .deny)
    }

    func testOnlyTheLicenseServerIsBlocked() {
        let rules = [NetworkRule(app: curl, host: "license.example.com", action: .deny)]
        XCTAssertEqual(NetworkRules.verdict(for: flow("license.example.com"), rules: rules), .deny)
        XCTAssertEqual(NetworkRules.verdict(for: flow("api.license.example.com"), rules: rules), .deny)
        XCTAssertEqual(NetworkRules.verdict(for: flow("example.com"), rules: rules), .allow)
        XCTAssertEqual(NetworkRules.verdict(for: flow("notlicense.example.com"), rules: rules), .allow)
    }

    func testDenyWinsBetweenEqualRules() {
        let rules = [NetworkRule(app: curl, host: "example.com", action: .allow),
                     NetworkRule(app: curl, host: "example.com", action: .deny)]
        XCTAssertEqual(NetworkRules.verdict(for: flow("example.com"), rules: rules), .deny)
    }

    func testAnAddressWithoutANameIsMatchedThroughTheResolvedHost() {
        let rules = [NetworkRule(app: curl, host: "example.com", action: .deny)]
        let resolved = ["example.com": Set(["93.184.216.34"])]
        XCTAssertEqual(NetworkRules.verdict(for: flow(nil), rules: rules, addresses: resolved), .deny)
        XCTAssertEqual(NetworkRules.verdict(for: flow(nil, "8.8.8.8"), rules: rules, addresses: resolved), .allow)
    }

    func testARuleCanNameAnAddress() {
        let rules = [NetworkRule(app: curl, host: "10.0.0.5", action: .deny)]
        XCTAssertEqual(NetworkRules.verdict(for: flow(nil, "10.0.0.5"), rules: rules), .deny)
        XCTAssertEqual(NetworkRules.hostsToResolve(rules), [])
    }

    func testHostsAreComparedWithoutCaseOrTrailingDot() {
        let rules = [NetworkRule(app: curl, host: "Example.COM.", action: .deny)]
        XCTAssertEqual(NetworkRules.verdict(for: flow("example.com"), rules: rules), .deny)
        XCTAssertEqual(NetworkRules.verdict(for: flow("EXAMPLE.com."), rules: rules), .deny)
    }

    func testAHelperProcessCountsForItsProgram() {
        let rules = [NetworkRule(app: "com.example.app", action: .deny)]
        let helper = NetworkFlow(apps: ["com.example.app", "com.example.app.helper"], hostname: "x.com", address: "1.2.3.4")
        XCTAssertEqual(NetworkRules.verdict(for: helper, rules: rules), .deny)
    }

    func testRulesSurviveTheTripToTheFilter() {
        let rules = [NetworkRule(app: curl, host: "example.com", action: .deny), NetworkRule(app: "a", action: .allow)]
        XCTAssertEqual(NetworkRules.decode(NetworkRules.encode(rules)), rules)
        XCTAssertEqual(NetworkRules.decode(nil), [])
        XCTAssertEqual(NetworkRules.decode(Data("garbage".utf8)), [])
    }
}

final class NetworkModulePlacementTests: XCTestCase {
    func testANewNetworkModuleJoinsTheMonitorsSpace() {
        var model = PanelTabsModel(tabs: [
            PanelTab(icon: "house", moduleKeys: ["timer"]),
            PanelTab(icon: "display", moduleKeys: ["system", "speedtest"]),
        ])
        model.ensure(modules: ["network", "color"])
        XCTAssertEqual(model.tabs[1].moduleKeys, ["system", "speedtest", "network"])
        XCTAssertEqual(model.tabs[0].moduleKeys, ["timer", "color"])
    }

    func testWithoutAMonitorSpaceItLandsOnTheFirst() {
        var model = PanelTabsModel(tabs: [PanelTab(icon: "house", moduleKeys: ["timer"])])
        model.ensure(modules: ["network"])
        XCTAssertEqual(model.tabs[0].moduleKeys, ["timer", "network"])
    }

    func testTheNetworkModuleIsInTheMacGroupOfTheOnboarding() {
        XCTAssertTrue(ModuleCatalog.onboardingGroups.contains { $0.modules.contains("network") })
    }
}

final class NetworkQuestionTests: XCTestCase {
    func testOnlyAConnectionNoRuleSpeaksAboutIsAskedAbout() {
        let flow = NetworkFlow(apps: ["com.a"], hostname: "x.com", address: "1.1.1.1")
        XCTAssertNil(NetworkRules.ruled(flow, rules: []))
        XCTAssertNil(NetworkRules.ruled(flow, rules: [NetworkRule(app: "com.b", action: .deny)]))
        XCTAssertEqual(NetworkRules.ruled(flow, rules: [NetworkRule(app: "com.a", action: .allow)]), .allow)
        XCTAssertEqual(NetworkRules.ruled(flow, rules: [NetworkRule(app: "*", host: "x.com", action: .deny)]), .deny)
    }
}
