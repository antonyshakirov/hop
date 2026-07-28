import XCTest
@testable import HopCore

final class TodosTests: XCTestCase {

    // MARK: - TodoList model

    func testAddAppendsAtBottomAndReturnsID() {
        var list = TodoList.empty
        let first = list.add(text: "buy milk")
        let second = list.add(text: "call bank")

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(list.items.map(\.text), ["buy milk", "call bank"])
        XCTAssertEqual(list.items.first?.id, first)
        XCTAssertEqual(list.items.last?.id, second)
    }

    func testAddTrimsWhitespace() {
        var list = TodoList.empty
        list.add(text: "  padded  ")
        XCTAssertEqual(list.items.first?.text, "padded")
    }

    func testAddEmptyOrWhitespaceIsNoOp() {
        var list = TodoList.empty
        XCTAssertNil(list.add(text: ""))
        XCTAssertNil(list.add(text: "   \n"))
        XCTAssertTrue(list.items.isEmpty)
    }

    func testNewItemIsNotDone() {
        var list = TodoList.empty
        list.add(text: "task")
        XCTAssertEqual(list.items.first?.done, false)
    }

    func testToggleFlipsDoneAndKeepsPosition() {
        var list = TodoList.empty
        list.add(text: "a")
        let bID = list.add(text: "b")!
        list.add(text: "c")

        list.toggle(bID)

        XCTAssertEqual(list.items.map(\.text), ["a", "b", "c"], "completing keeps order")
        XCTAssertEqual(list.items[1].done, true)

        list.toggle(bID)
        XCTAssertEqual(list.items[1].done, false, "toggle is symmetric")
        XCTAssertEqual(list.items.map(\.text), ["a", "b", "c"])
    }

    func testToggleUnknownIDIsNoOp() {
        var list = TodoList.empty
        list.add(text: "a")
        list.toggle(UUID())
        XCTAssertEqual(list.items.first?.done, false)
    }

    func testDeleteRemovesByID() {
        var list = TodoList.empty
        let aID = list.add(text: "a")!
        list.add(text: "b")

        list.delete(aID)

        XCTAssertEqual(list.items.map(\.text), ["b"])
    }

    func testDeleteUnknownIDIsNoOp() {
        var list = TodoList.empty
        list.add(text: "a")
        list.delete(UUID())
        XCTAssertEqual(list.items.count, 1)
    }

    // MARK: - Reordering: move(from:to:)

    func testMoveReordersItems() {
        var list = TodoList.empty
        list.add(text: "a")
        list.add(text: "b")
        list.add(text: "c")

        list.move(from: 0, to: 2)   // a to the end
        XCTAssertEqual(list.items.map(\.text), ["b", "c", "a"])
    }

    func testMoveClampsDestinationPastTheEnd() {
        var list = TodoList.empty
        list.add(text: "a")
        list.add(text: "b")
        list.add(text: "c")

        list.move(from: 2, to: 99)   // clamps to last
        XCTAssertEqual(list.items.map(\.text), ["a", "b", "c"])

        list.move(from: 0, to: 99)
        XCTAssertEqual(list.items.map(\.text), ["b", "c", "a"])
    }

    func testMoveFromOutOfRangeIsNoOp() {
        var list = TodoList.empty
        list.add(text: "a")
        list.add(text: "b")

        list.move(from: 5, to: 0)
        XCTAssertEqual(list.items.map(\.text), ["a", "b"])
    }

    func testReorderedListPersistsThroughTheStore() throws {
        var list = TodoList.empty
        list.add(text: "a")
        list.add(text: "b")
        list.add(text: "c")
        list.move(from: 0, to: 2)   // [b, c, a]

        try TodosStore.save(list, to: dir)

        XCTAssertEqual(TodosStore.load(from: dir).items.map(\.text), ["b", "c", "a"])
    }

    // MARK: - TodosStore

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("TodosStoreTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        dir = nil
        super.tearDown()
    }

    func testLoadFromEmptyDirectoryReturnsEmpty() {
        XCTAssertEqual(TodosStore.load(from: dir), .empty)
    }

    func testSaveThenLoadRoundTrips() throws {
        var list = TodoList.empty
        let id = list.add(text: "ship 8.4")!
        list.add(text: "write tests")
        list.toggle(id)

        try TodosStore.save(list, to: dir)

        XCTAssertEqual(TodosStore.load(from: dir), list)
    }

    func testTolerantDecodeOfMissingItemsKeyYieldsEmpty() throws {
        let fileURL = dir.appendingPathComponent("todos.json")
        try Data("{}".utf8).write(to: fileURL)

        let loaded = TodosStore.load(from: dir)

        XCTAssertEqual(loaded, .empty)
        // A well-formed (if minimal) file decodes — it is NOT treated as
        // corrupt, so no backup is written.
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("todos.json.bak").path))
    }

    func testLoadOfGarbageBytesReturnsEmptyAndBacksUpTheFile() throws {
        let fileURL = dir.appendingPathComponent("todos.json")
        let garbage = Data([0xFF, 0x00, 0xDE, 0xAD, 0xBE, 0xEF])
        try garbage.write(to: fileURL)

        let loaded = TodosStore.load(from: dir)

        XCTAssertEqual(loaded, .empty)
        let bakURL = dir.appendingPathComponent("todos.json.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakURL.path))
        XCTAssertEqual(try Data(contentsOf: bakURL), garbage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testLoadOfGarbageBytesReplacesAnOlderBackup() throws {
        let fileURL = dir.appendingPathComponent("todos.json")
        let bakURL = dir.appendingPathComponent("todos.json.bak")
        try Data("stale backup".utf8).write(to: bakURL)
        let garbage = Data([0x01, 0x02, 0x03])
        try garbage.write(to: fileURL)

        let loaded = TodosStore.load(from: dir)

        XCTAssertEqual(loaded, .empty)
        XCTAssertEqual(try Data(contentsOf: bakURL), garbage)
    }

    /// A file that EXISTS but cannot be read (a directory in its place) is
    /// backed up before the next save can overwrite it, not silently dropped.
    func testLoadOfUnreadableFileBacksItUpBeforeOverwrite() throws {
        let fileURL = dir.appendingPathComponent("todos.json")
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)

        let loaded = TodosStore.load(from: dir)

        XCTAssertEqual(loaded, .empty)
        let bakURL = dir.appendingPathComponent("todos.json.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Note, reminder and importance fields

    /// A file written before these fields existed must load with defaults. A
    /// decode failure would move the user's list aside as a .bak.
    func testDecodesLegacyItemWithoutNewKeys() throws {
        let json = Data("""
        {"items":[{"id":"0E7A6E1A-0000-4000-8000-000000000001","text":"a","done":true}]}
        """.utf8)

        let list = try JSONDecoder().decode(TodoList.self, from: json)

        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.items[0].note, "")
        XCTAssertNil(list.items[0].remindAt)
        XCTAssertEqual(list.items[0].repeatDays, [])
        XCTAssertNil(list.items[0].snoozedUntil)
        XCTAssertNil(list.items[0].firedAt)
        XCTAssertFalse(list.items[0].firedUnseen)
        XCTAssertFalse(list.items[0].important)
    }

    func testWeekdaysAreSortedDeduplicatedAndRangeChecked() {
        XCTAssertEqual(TodoItem.normalizedWeekdays([7, 1, 1, 0, 8, 4, -2]), [1, 4, 7])
        XCTAssertEqual(TodoItem.normalizedWeekdays([]), [])
    }

    func testDecodeNormalizesStoredWeekdays() throws {
        let json = Data("""
        {"items":[{"id":"0E7A6E1A-0000-4000-8000-000000000002","text":"a","done":false,\
        "repeatDays":[5,2,2,99]}]}
        """.utf8)

        let list = try JSONDecoder().decode(TodoList.self, from: json)

        XCTAssertEqual(list.items[0].repeatDays, [2, 5])
    }

    func testTrackerTaskDecodesWithoutTheNewKeys() throws {
        let json = Data("""
        {"id":"0E7A6E1A-0000-4000-8000-000000000003","name":"a"}
        """.utf8)

        let task = try JSONDecoder().decode(TrackerTask.self, from: json)

        XCTAssertEqual(task.note, "")
        XCTAssertFalse(task.important)
    }

    // MARK: - Editing mutators

    func testSetTextTrimsAndRejectsBlank() {
        var list = TodoList(items: [TodoItem(text: "a")])
        let id = list.items[0].id

        list.setText(id, to: "  new title  ")
        XCTAssertEqual(list.items[0].text, "new title")

        list.setText(id, to: "   ")
        XCTAssertEqual(list.items[0].text, "new title", "a blank commit never wipes the title")
    }

    func testSetNoteStoresTheComment() {
        var list = TodoList(items: [TodoItem(text: "a")])
        let id = list.items[0].id

        list.setNote(id, to: "  ask for the second copy  ")

        XCTAssertEqual(list.items[0].note, "ask for the second copy")
    }

    func testSetReminderNormalizesWeekdaysAndClearsAStaleFiring() {
        var list = TodoList(items: [TodoItem(text: "a", firedAt: .distantPast, firedUnseen: true)])
        let id = list.items[0].id
        let when = Date(timeIntervalSinceReferenceDate: 800_000_000)

        list.setReminder(id, at: when, repeatDays: [5, 2, 2])

        XCTAssertEqual(list.items[0].remindAt, when)
        XCTAssertEqual(list.items[0].repeatDays, [2, 5])
        XCTAssertNil(list.items[0].firedAt, "a re-armed reminder is not an old firing")
        XCTAssertFalse(list.items[0].firedUnseen)
    }

    func testClearReminderRemovesEveryTraceOfIt() {
        var list = TodoList(items: [TodoItem(text: "a", remindAt: Date(), repeatDays: [3],
                                             snoozedUntil: Date(), firedUnseen: true)])
        let id = list.items[0].id

        list.clearReminder(id)

        XCTAssertNil(list.items[0].remindAt)
        XCTAssertEqual(list.items[0].repeatDays, [])
        XCTAssertNil(list.items[0].snoozedUntil)
        XCTAssertFalse(list.items[0].firedUnseen)
    }

    func testSnoozeSetsTheNewFiringAndClearsTheUnseenMark() {
        var list = TodoList(items: [TodoItem(text: "a", remindAt: Date(), firedUnseen: true)])
        let id = list.items[0].id
        let until = Date(timeIntervalSinceReferenceDate: 900_000_000)

        list.snooze(id, until: until)

        XCTAssertEqual(list.items[0].snoozedUntil, until)
        XCTAssertFalse(list.items[0].firedUnseen, "snoozing is an acknowledgement")
    }

    func testAcknowledgeClearsEveryUnseenFiring() {
        var list = TodoList(items: [TodoItem(text: "a", firedUnseen: true),
                                    TodoItem(text: "b", firedUnseen: true)])

        XCTAssertTrue(list.acknowledgeFirings())
        XCTAssertFalse(list.hasUnseenFiring)
        XCTAssertFalse(list.acknowledgeFirings(), "nothing left to acknowledge")
    }

    func testUnknownIDIsANoOpForEveryMutator() {
        var list = TodoList(items: [TodoItem(text: "a")])
        let before = list
        let stranger = UUID()

        list.setText(stranger, to: "x")
        list.setNote(stranger, to: "x")
        list.setImportant(stranger, true)
        list.setReminder(stranger, at: Date(), repeatDays: [1])
        list.clearReminder(stranger)
        list.snooze(stranger, until: Date())

        XCTAssertEqual(list, before)
    }

    func testNewFieldsSurviveTheStoreRoundTrip() throws {
        let at = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let list = TodoList(items: [
            TodoItem(text: "a", note: "call first", remindAt: at, repeatDays: [3, 5],
                     firedAt: at, firedUnseen: true, important: true)
        ])

        try TodosStore.save(list, to: dir)

        XCTAssertEqual(TodosStore.load(from: dir), list)
    }
}
