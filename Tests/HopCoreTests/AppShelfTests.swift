import XCTest
@testable import HopCore

/// Shelves of apps: the grid model behind the launcher module — several shelves,
/// each with its own icons, reordered and trimmed the way a home screen is.
final class AppShelfTests: XCTestCase {

    private func item(_ name: String) -> ShelfItem {
        ShelfItem(path: "/Applications/\(name).app", bundleIdentifier: "com.test.\(name)", name: name)
    }

    // MARK: - One shelf

    func testAddingAppends() {
        var shelf = AppShelf()
        XCTAssertTrue(shelf.add(item("Safari")))
        XCTAssertTrue(shelf.add(item("Mail")))
        XCTAssertEqual(shelf.items.map(\.name), ["Safari", "Mail"])
    }

    func testTheSameAppIsNotAddedTwice() {
        var shelf = AppShelf()
        shelf.add(item("Safari"))
        XCTAssertFalse(shelf.add(item("Safari")), "dropping it again is a no-op, not a duplicate")
        XCTAssertEqual(shelf.items.count, 1)
    }

    func testAFullShelfRefusesMore() {
        var shelf = AppShelf()
        for index in 0..<shelf.capacity { shelf.add(item("App\(index)")) }
        XCTAssertTrue(shelf.isFull)
        XCTAssertFalse(shelf.add(item("OneMore")))
        XCTAssertEqual(shelf.items.count, shelf.capacity, "eight rows of its own width, and no further")
    }

    func testRemoving() {
        var shelf = AppShelf()
        shelf.add(item("Safari"))
        let mail = item("Mail")
        shelf.add(mail)
        shelf.remove(mail.id)
        XCTAssertEqual(shelf.items.map(\.name), ["Safari"])
    }

    // MARK: - Moving, the way a home screen moves

    func testMovingShufflesTheOthersAlong() {
        var shelf = AppShelf()
        let a = item("A"), b = item("B"), c = item("C")
        shelf.add(a); shelf.add(b); shelf.add(c)
        shelf.move(c.id, to: 0)
        XCTAssertEqual(shelf.items.map(\.name), ["C", "A", "B"])
    }

    func testMovingToTheEnd() {
        var shelf = AppShelf()
        let a = item("A"), b = item("B"), c = item("C")
        shelf.add(a); shelf.add(b); shelf.add(c)
        shelf.move(a.id, to: 2)
        XCTAssertEqual(shelf.items.map(\.name), ["B", "C", "A"])
    }

    func testMovingClampsRatherThanCrashes() {
        var shelf = AppShelf()
        let a = item("A"), b = item("B")
        shelf.add(a); shelf.add(b)
        shelf.move(a.id, to: 99)
        XCTAssertEqual(shelf.items.map(\.name), ["B", "A"])
        shelf.move(b.id, to: -5)
        XCTAssertEqual(shelf.items.map(\.name), ["B", "A"])
    }

    func testMovingAnUnknownIconIsANoOp() {
        var shelf = AppShelf()
        shelf.add(item("A"))
        shelf.move(UUID(), to: 0)
        XCTAssertEqual(shelf.items.count, 1)
    }

    // MARK: - Several shelves

    func testEachShelfHasItsOwnModuleKey() {
        var shelves = AppShelves()
        let first = shelves.addShelf()
        let second = shelves.addShelf()
        XCTAssertNotEqual(first.moduleKey, second.moduleKey)
        XCTAssertEqual(shelves.moduleKeys.count, 2)
        XCTAssertTrue(first.moduleKey.hasPrefix("apps:"))
    }

    func testAModuleKeyPointsBackAtItsShelf() {
        var shelves = AppShelves()
        let shelf = shelves.addShelf()
        XCTAssertEqual(AppShelves.shelfID(fromModuleKey: shelf.moduleKey), shelf.id)
    }

    func testAnotherModulesKeyNamesNoShelf() {
        XCTAssertNil(AppShelves.shelfID(fromModuleKey: "timer"))
        XCTAssertNil(AppShelves.shelfID(fromModuleKey: "apps:not-a-uuid"))
    }

    func testShelvesAreAddressableByID() {
        var shelves = AppShelves()
        let shelf = shelves.addShelf()
        var updated = shelf
        updated.add(item("Safari"))
        shelves[shelf.id] = updated
        XCTAssertEqual(shelves[shelf.id]?.items.count, 1)
        shelves.removeShelf(shelf.id)
        XCTAssertNil(shelves[shelf.id])
        XCTAssertTrue(shelves.shelves.isEmpty)
    }

    // MARK: - Its own name and label setting

    func testAShelfStartsUnnamedAndShowingLabels() {
        let shelf = AppShelf()
        XCTAssertEqual(shelf.title, "", "the first grid should be usable without naming it")
        XCTAssertTrue(shelf.showsLabels)
    }

    func testNameAndLabelSettingSurviveStorage() throws {
        var shelves = AppShelves()
        var shelf = shelves.addShelf()
        shelf.title = "work"
        shelf.showsLabels = false
        shelf.add(item("Safari"))
        shelves[shelf.id] = shelf

        let data = try JSONEncoder().encode(shelves)
        let decoded = try JSONDecoder().decode(AppShelves.self, from: data)

        XCTAssertEqual(decoded.shelves.first?.title, "work")
        XCTAssertEqual(decoded.shelves.first?.showsLabels, false)
    }

    func testAShelfFromBeforeTheseFieldsStillLoads() throws {
        let json = Data(#"{"id":"11111111-2222-4333-8444-555555555555","items":[]}"#.utf8)
        let shelf = try JSONDecoder().decode(AppShelf.self, from: json)
        XCTAssertEqual(shelf.title, "")
        XCTAssertTrue(shelf.showsLabels, "labels stay on for a grid that never chose")
    }

    // MARK: - Storage

    func testRoundTripsThroughJSON() throws {
        var shelves = AppShelves()
        var shelf = shelves.addShelf()
        shelf.add(item("Safari"))
        shelves[shelf.id] = shelf

        let data = try JSONEncoder().encode(shelves)
        XCTAssertEqual(try JSONDecoder().decode(AppShelves.self, from: data), shelves)
    }

    func testAFileWithoutTheKeyLoadsEmptyRatherThanFailing() throws {
        let decoded = try JSONDecoder().decode(AppShelves.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, .empty)
    }

    func testAnItemWithoutAStoredNameFallsBackToItsFileName() throws {
        let json = Data(#"{"path":"/Applications/Safari.app"}"#.utf8)
        let item = try JSONDecoder().decode(ShelfItem.self, from: json)
        XCTAssertEqual(item.name, "Safari.app")
        XCTAssertNil(item.bundleIdentifier)
    }

    // MARK: - Matching keys to shelves

    func testAKeyNamesItsShelfWhateverCaseTheUUIDIsWrittenIn() {
        let id = UUID(uuidString: "BB658A89-3685-4619-8267-DC2E7326D6B4")!
        let lower = "apps:bb658a89-3685-4619-8267-dc2e7326d6b4"
        XCTAssertEqual(AppShelves.shelfID(fromModuleKey: lower), id)
        XCTAssertEqual(AppShelves.moduleKeys(for: id, in: ["timer", lower]), [lower],
                       "matched by id, not by the key's text")
    }

    func testMatchingIgnoresOtherShelves() {
        var shelves = AppShelves()
        let a = shelves.addShelf(), b = shelves.addShelf()
        let keys = [a.moduleKey, b.moduleKey, "timer"]
        XCTAssertEqual(AppShelves.moduleKeys(for: a.id, in: keys), [a.moduleKey])
    }

    func testAKeyWhoseShelfIsGoneIsAnOrphan() {
        var shelves = AppShelves()
        let shelf = shelves.addShelf()
        let ghost = "apps:bb658a89-3685-4619-8267-dc2e7326d6b4"
        XCTAssertEqual(shelves.orphanedModuleKeys(in: [shelf.moduleKey, ghost, "timer"]), [ghost])
        shelves.removeShelf(shelf.id)
        XCTAssertEqual(shelves.orphanedModuleKeys(in: [shelf.moduleKey]), [shelf.moduleKey])
    }

    func testTheGridIsEightAcrossAndEightDownByDefault() {
        XCTAssertEqual(AppShelf.defaultColumns, 8)
        XCTAssertEqual(AppShelf.rows, 8)
        XCTAssertEqual(AppShelf().capacity, 64)
    }

    func testAGridCanBeThreeToNineAcross() {
        XCTAssertEqual(AppShelf.columnRange, 3...9)
        XCTAssertEqual(AppShelf(columns: 3).columns, 3)
        XCTAssertEqual(AppShelf(columns: 5).capacity, 40, "eight rows of whatever the width is")
    }

    func testAWidthOutsideTheRangeIsClamped() {
        XCTAssertEqual(AppShelf(columns: 1).columns, 3)
        XCTAssertEqual(AppShelf(columns: 40).columns, 9)
        var shelf = AppShelf()
        shelf.columns = 0
        XCTAssertEqual(shelf.columns, 3)
    }

    func testANarrowerGridKeepsTheIconsThatNoLongerFit() throws {
        // widening it again has to bring them back, so nothing is thrown away
        var shelf = AppShelf(columns: 9)
        for index in 0..<40 { shelf.add(item("App\(index)")) }
        shelf.columns = 3
        XCTAssertEqual(shelf.items.count, 40)
        XCTAssertTrue(shelf.isFull, "24 fit a grid three across")
    }

    func testAGridWrittenBeforeTheWidthExistedLoadsAtTheDefault() throws {
        let json = Data(#"{"id":"\#(UUID().uuidString)","items":[],"title":"","showsLabels":true}"#.utf8)
        let shelf = try JSONDecoder().decode(AppShelf.self, from: json)
        XCTAssertEqual(shelf.columns, AppShelf.defaultColumns)
    }
}
