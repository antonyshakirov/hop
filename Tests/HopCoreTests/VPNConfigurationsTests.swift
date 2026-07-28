import XCTest
@testable import HopCore

/// Reading the system's own VPN list. The fixtures are the real output of
/// `scutil --nc list` on a Mac with two configurations, one of them connected.
final class VPNConfigurationsTests: XCTestCase {

    private let realOutput = """
    Available network connection services in the current set (*=enabled):
    * (Connected)      6A7852E0-3E2A-4C8B-82BA-33132F2B3197 VPN (hidemyname.vpn) "hidemy.name vpn (OpenVPN)"      [VPN:hidemyname.vpn]
    * (Disconnected)   0DDD2941-7A01-42A2-AD64-665126E17353 VPN (com.vanyavpn.macos.client) "Germany"                   [VPN:com.vanyavpn.macos.client]
    """

    func testReadsBothConfigurations() {
        let list = VPNConfigurations.parseList(realOutput)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.map(\.name), ["hidemy.name vpn (OpenVPN)", "Germany"])
    }

    func testCarriesTheIdentifierTheSystemCommandNeeds() {
        let list = VPNConfigurations.parseList(realOutput)
        XCTAssertEqual(list.first?.id, "6A7852E0-3E2A-4C8B-82BA-33132F2B3197")
    }

    func testCarriesTheOwningApp() {
        let list = VPNConfigurations.parseList(realOutput)
        XCTAssertEqual(list.first?.bundleIdentifier, "hidemyname.vpn")
        XCTAssertEqual(list.last?.bundleIdentifier, "com.vanyavpn.macos.client")
    }

    func testReadsTheState() {
        let list = VPNConfigurations.parseList(realOutput)
        XCTAssertEqual(list.first?.state, .connected)
        XCTAssertTrue(list.first!.state.isOn)
        XCTAssertEqual(list.last?.state, .disconnected)
        XCTAssertFalse(list.last!.state.isOn)
    }

    func testHeaderAndBlankLinesAreIgnored() {
        XCTAssertTrue(VPNConfigurations.parseList("").isEmpty)
        XCTAssertTrue(VPNConfigurations.parseList(
            "Available network connection services in the current set (*=enabled):").isEmpty)
    }

    func testANonVPNServiceIsSkipped() {
        let output = """
        * (Connected)      11111111-2222-4333-8444-555555555555 PPP (ppp) "Dial-up"  [PPP:ppp]
        """
        XCTAssertTrue(VPNConfigurations.parseList(output).isEmpty)
    }

    func testAConfigurationWithoutAnAppStillReads() {
        // a corporate IKEv2 profile has no app behind it
        let output = """
        * (Disconnected)   22222222-3333-4444-8555-666666666666 VPN "Work IKEv2"  [VPN]
        """
        let list = VPNConfigurations.parseList(output)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.name, "Work IKEv2")
        XCTAssertNil(list.first?.bundleIdentifier)
    }

    func testInBetweenStatesAreBusyRatherThanOn() {
        for (word, expected) in [("Connecting", VPNConfiguration.State.connecting),
                                 ("Disconnecting", .disconnecting)] {
            let output = """
            * (\(word))   33333333-4444-4555-8666-777777777777 VPN (x.y) "Any"  [VPN:x.y]
            """
            let state = VPNConfigurations.parseList(output).first?.state
            XCTAssertEqual(state, expected)
            XCTAssertTrue(state!.isBusy)
            XCTAssertFalse(state!.isOn)
        }
    }

    // MARK: - What the row is called

    func testTheAppNameLeadsAndTheConfigurationFollows() {
        // the real confusion: the app has its own name while the configuration
        // it created is called "Germany"
        var configuration = VPNConfigurations.parseList(realOutput)[1]
        configuration.appName = "VanyaVPN"
        XCTAssertEqual(configuration.title, "VanyaVPN")
        XCTAssertEqual(configuration.subtitle, "Germany")
    }

    func testWithoutAnAppTheConfigurationNameLeadsAlone() {
        let configuration = VPNConfigurations.parseList(realOutput)[1]
        XCTAssertEqual(configuration.title, "Germany")
        XCTAssertNil(configuration.subtitle)
    }

    func testAnAppNamedLikeItsConfigurationIsNotRepeated() {
        var configuration = VPNConfigurations.parseList(realOutput)[0]
        configuration.appName = "hidemy.name vpn (OpenVPN)"
        XCTAssertNil(configuration.subtitle, "the same words twice is noise")
    }

    func testAProtocolNameIsNotWorthARow() {
        // "hidemy.name vpn (OpenVPN)" under an app called "hidemy.name VPN" leaves
        // only the protocol, which tells the user nothing they can act on
        var configuration = VPNConfigurations.parseList(realOutput)[0]
        configuration.appName = "hidemy.name VPN"
        XCTAssertNil(configuration.subtitle)
    }

    func testACountrySurvivesTheFilter() {
        var configuration = VPNConfigurations.parseList(realOutput)[1]
        configuration.appName = "VanyaVPN"
        XCTAssertEqual(configuration.subtitle, "Germany")
    }

    func testAProfileNameSurvivesToo() {
        var configuration = VPNConfiguration(id: "x", name: "Work Berlin IKEv2",
                                             bundleIdentifier: nil, state: .disconnected)
        configuration.appName = "Corporate"
        XCTAssertEqual(configuration.subtitle, "Work Berlin")
    }

    func testStatusOutputIsOneWord() {
        XCTAssertEqual(VPNConfigurations.parseStatus("Connected\nExtended Status <dictionary> {"),
                       .connected)
        XCTAssertEqual(VPNConfigurations.parseStatus("Disconnected"), .disconnected)
        XCTAssertEqual(VPNConfigurations.parseStatus("something else"), .unknown)
    }

    func testAnUnnamedConfigurationIsSkippedRatherThanShownBlank() {
        let output = """
        * (Connected)   44444444-5555-4666-8777-888888888888 VPN (x.y) ""  [VPN:x.y]
        """
        XCTAssertTrue(VPNConfigurations.parseList(output).isEmpty)
    }
}
