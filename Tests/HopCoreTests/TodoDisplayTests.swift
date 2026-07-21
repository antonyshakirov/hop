import XCTest
@testable import HopCore

/// Display-ordering + drag-clamping for the to-do list: completed items sink to
/// the bottom for display without ever mutating the stored order, and a drag is
/// clamped to the item's own group (active / completed).
final class TodoDisplayTests: XCTestCase {

    // Build a list of items with stable, readable ids so assertions can name them.
    private func make(_ spec: [(String, Bool)]) -> [TodoItem] {
        spec.map { TodoItem(id: id($0.0), text: $0.0, done: $0.1) }
    }
    private var idMap: [String: UUID] = [:]
    private func id(_ name: String) -> UUID {
        if let u = idMap[name] { return u }
        let u = UUID()
        idMap[name] = u
        return u
    }
    private func names(_ items: [TodoItem]) -> [String] { items.map(\.text) }

    // MARK: - order (active first, then completed; stable within each group)

    func testOrderPutsCompletedLast() {
        let items = make([("a", false), ("b", true), ("c", false), ("d", true)])
        XCTAssertEqual(names(TodoDisplay.order(items)), ["a", "c", "b", "d"])
    }

    func testOrderIsStableWithinGroups() {
        // stored order among actives (a,c,e) and among completed (b,d) is kept
        let items = make([("a", false), ("b", true), ("c", false), ("d", true), ("e", false)])
        XCTAssertEqual(names(TodoDisplay.order(items)), ["a", "c", "e", "b", "d"])
    }

    func testOrderAllActiveOrAllDoneIsIdentity() {
        let active = make([("a", false), ("b", false)])
        XCTAssertEqual(names(TodoDisplay.order(active)), ["a", "b"])
        let done = make([("a", true), ("b", true)])
        XCTAssertEqual(names(TodoDisplay.order(done)), ["a", "b"])
    }

    // MARK: - clampedInsertion (a drag never crosses the group boundary)

    func testActiveItemClampedAboveTheFirstCompleted() {
        // stored [a,b,c(done),d,e(done)] -> display [a,b,d,c,e], others of a = [b,d,c,e]
        // active group occupies display-others positions 0..1 (b,d): insert clamps to [0,2]
        let items = make([("a", false), ("b", false), ("c", true), ("d", false), ("e", true)])
        XCTAssertEqual(TodoDisplay.clampedInsertion(items, dragging: id("a"), rawInsertion: 4), 2,
                       "an active item cannot land among the completed pile")
        XCTAssertEqual(TodoDisplay.clampedInsertion(items, dragging: id("a"), rawInsertion: 0), 0)
        XCTAssertEqual(TodoDisplay.clampedInsertion(items, dragging: id("a"), rawInsertion: 1), 1)
    }

    func testCompletedItemClampedBelowTheLastActive() {
        // dragging c(done): display-others [a,b,d,e], completed group occupies position 3 (e)
        // insertion clamps to [3,4]
        let items = make([("a", false), ("b", false), ("c", true), ("d", false), ("e", true)])
        XCTAssertEqual(TodoDisplay.clampedInsertion(items, dragging: id("c"), rawInsertion: 0), 3,
                       "a completed item cannot rise above the active items")
        XCTAssertEqual(TodoDisplay.clampedInsertion(items, dragging: id("c"), rawInsertion: 4), 4)
    }

    // MARK: - reordered (only the dragged item moves; others keep their stored slot)

    func testReorderWithinActiveGroupMovesOnlyTheDragged() {
        // stored [a,b,c(done),d,e(done)]; move a to the end of the active group
        let items = make([("a", false), ("b", false), ("c", true), ("d", false), ("e", true)])
        let out = TodoDisplay.reordered(items, dragging: id("a"), toDisplayInsertion: 2)
        // display becomes [b,d,a,c,e]; stored keeps c between b and d, e last
        XCTAssertEqual(names(TodoDisplay.order(out)), ["b", "d", "a", "c", "e"])
        XCTAssertEqual(names(out), ["b", "c", "d", "a", "e"], "untouched items keep their stored positions")
    }

    func testReorderClampKeepsActiveItemOutOfCompletedPile() {
        let items = make([("a", false), ("b", false), ("c", true), ("d", false), ("e", true)])
        // try to drop a far past the boundary — it stays the LAST active item
        let out = TodoDisplay.reordered(items, dragging: id("a"), toDisplayInsertion: 9)
        XCTAssertEqual(names(TodoDisplay.order(out)), ["b", "d", "a", "c", "e"])
        XCTAssertTrue(out.first(where: { $0.text == "a" })!.done == false)
    }

    func testReorderWithinCompletedGroup() {
        // stored [a,b(done),c(done),d(done)] display [a,b,c,d]; move d up within done
        let items = make([("a", false), ("b", true), ("c", true), ("d", true)])
        // display-others are [a,b,c]; an insertion index of 2 drops d between b and
        // c (index 1 would put it at the very top of the completed group, before b)
        let out = TodoDisplay.reordered(items, dragging: id("d"), toDisplayInsertion: 2)
        XCTAssertEqual(names(TodoDisplay.order(out)), ["a", "b", "d", "c"])

        // insertion index 1 clamps to the top of the completed group (before b)
        let top = TodoDisplay.reordered(items, dragging: id("d"), toDisplayInsertion: 1)
        XCTAssertEqual(names(TodoDisplay.order(top)), ["a", "d", "b", "c"])
    }

    func testReorderAloneInGroupIsNoOp() {
        // a is the only active item — it cannot move within a group of one
        let items = make([("a", false), ("b", true), ("c", true)])
        let out = TodoDisplay.reordered(items, dragging: id("a"), toDisplayInsertion: 0)
        XCTAssertEqual(names(out), ["a", "b", "c"])
    }

    func testReorderUnknownIDIsNoOp() {
        let items = make([("a", false), ("b", false)])
        let out = TodoDisplay.reordered(items, dragging: UUID(), toDisplayInsertion: 1)
        XCTAssertEqual(names(out), ["a", "b"])
    }

    // MARK: - toggle keeps stored order; unchecking restores the display slot

    func testToggleDoesNotMutateStoredOrderAndUncheckRestoresSlot() {
        var list = TodoList(items: make([("a", false), ("b", false), ("c", false)]))
        list.toggle(id("b"))
        XCTAssertEqual(names(list.items), ["a", "b", "c"], "stored order is untouched by completing")
        XCTAssertEqual(names(TodoDisplay.order(list.items)), ["a", "c", "b"], "b sinks in display")
        list.toggle(id("b"))
        XCTAssertEqual(names(TodoDisplay.order(list.items)), ["a", "b", "c"], "unchecking returns b to its slot")
    }
}
