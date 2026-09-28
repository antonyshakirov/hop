import XCTest
@testable import Hop

final class PanelSpaceHeightCacheTests: XCTestCase {
    func testExpandedCardCannotLeaveItsHeightForTheNextVisit() {
        let space = UUID()
        var cache = PanelSpaceHeightCache()

        cache.store(190, for: space, revision: cache.revision(for: space))
        XCTAssertEqual(cache.height(for: space), 190)

        let oldRevision = cache.revision(for: space)
        cache.setExpanded(true, module: "tracker", in: space)
        XCTAssertNil(cache.height(for: space))
        cache.store(340, for: space, revision: cache.revision(for: space))
        XCTAssertNil(cache.height(for: space))

        cache.setExpanded(false, module: "tracker", in: space)
        cache.store(340, for: space, revision: oldRevision)
        XCTAssertNil(cache.height(for: space))
        cache.store(190, for: space, revision: cache.revision(for: space))
        XCTAssertEqual(cache.height(for: space), 190)
    }

    func testOneCollapsedModuleDoesNotCacheWhileAnotherIsExpanded() {
        let space = UUID()
        var cache = PanelSpaceHeightCache()
        cache.setExpanded(true, module: "tracker", in: space)
        cache.setExpanded(true, module: "todos", in: space)
        cache.setExpanded(false, module: "tracker", in: space)
        cache.store(300, for: space, revision: cache.revision(for: space))
        XCTAssertNil(cache.height(for: space))

        cache.setExpanded(false, module: "todos", in: space)
        cache.store(190, for: space, revision: cache.revision(for: space))
        XCTAssertEqual(cache.height(for: space), 190)
    }

    func testTabReconfigurationKeepsExpandedCardOutOfTheCache() {
        let space = UUID()
        var cache = PanelSpaceHeightCache()
        cache.setExpanded(true, module: "todos", in: space)
        let beforeChange = cache.revision(for: space)
        cache.clear()
        cache.store(320, for: space, revision: cache.revision(for: space))
        XCTAssertNil(cache.height(for: space))

        cache.setExpanded(false, module: "todos", in: space)
        cache.store(320, for: space, revision: beforeChange)
        XCTAssertNil(cache.height(for: space))
    }
}
