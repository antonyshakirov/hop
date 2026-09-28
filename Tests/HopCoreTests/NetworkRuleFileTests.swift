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
        XCTAssertEqual(NetworkRules.verdict(for: flow("tracker.com"), rules: rules), .allow)
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
