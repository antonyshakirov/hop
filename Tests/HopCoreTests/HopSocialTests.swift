import XCTest
@testable import HopCore

final class HopSocialTests: XCTestCase {
    func testEveryLanguageButRussianShowsInstagramAndX() {
        XCTAssertEqual(HopSocial.links(forLanguage: "en").map(\.label), ["Instagram", "X"])
        XCTAssertEqual(HopSocial.links(forLanguage: "de").map(\.url),
                       ["https://www.instagram.com/hop.tools/", "https://x.com/hoptools"])
        XCTAssertEqual(HopSocial.links(forLanguage: "ru"), [])
    }
}
