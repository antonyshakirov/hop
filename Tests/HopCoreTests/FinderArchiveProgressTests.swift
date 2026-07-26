import XCTest
@testable import HopCore

final class FinderArchiveProgressTests: XCTestCase {
    func testNewProgressStartsVisibleAndExtracting() {
        let progress = FinderArchiveProgressState(fileName: "photos.rar")

        XCTAssertEqual(progress.fileName, "photos.rar")
        XCTAssertEqual(progress.phase, .extracting)
        XCTAssertTrue(progress.shouldKeepWindowOpen)
    }

    func testHelperPreparationKeepsWindowOpen() {
        var progress = FinderArchiveProgressState(fileName: "photos.rar")

        progress.receive(.waitingForHelper)

        XCTAssertEqual(progress.phase, .waitingForHelper)
        XCTAssertTrue(progress.shouldKeepWindowOpen)
    }

    func testSuccessClosesWindow() {
        var progress = FinderArchiveProgressState(fileName: "photos.zip")

        progress.receive(.succeeded)

        XCTAssertEqual(progress.phase, .succeeded)
        XCTAssertFalse(progress.shouldKeepWindowOpen)
    }

    func testFailureKeepsWindowOpenWithReason() {
        var progress = FinderArchiveProgressState(fileName: "photos.zip")

        progress.receive(.failed(.denied))

        XCTAssertEqual(progress.phase, .failed(.denied))
        XCTAssertTrue(progress.shouldKeepWindowOpen)
    }

    func testBatchClosesOnlyAfterEveryArchiveSucceeds() {
        let first = UUID()
        let second = UUID()
        var batch = FinderArchiveBatchState(files: [
            (id: first, fileName: "one.zip"),
            (id: second, fileName: "two.7z"),
        ])

        batch.receive(.succeeded, for: first)
        XCTAssertEqual(batch.presentation, .progress)

        batch.receive(.succeeded, for: second)
        XCTAssertEqual(batch.presentation, .close)
    }

    func testAnyBatchFailureKeepsTheWindowAsAnErrorSurface() {
        let first = UUID()
        let second = UUID()
        var batch = FinderArchiveBatchState(files: [
            (id: first, fileName: "good.zip"),
            (id: second, fileName: "broken.zip"),
        ])

        batch.receive(.succeeded, for: first)
        batch.receive(.failed(.tool), for: second)

        XCTAssertEqual(batch.presentation, .failure)
    }

    func testUnknownArchiveUpdateCannotAccidentallyCloseBatch() {
        let known = UUID()
        var batch = FinderArchiveBatchState(files: [
            (id: known, fileName: "one.zip"),
        ])

        batch.receive(.succeeded, for: UUID())

        XCTAssertEqual(batch.presentation, .progress)
        XCTAssertEqual(batch.items.first?.progress.phase, .extracting)
    }

    func testFinderInvocationNeverRecordsAManualJob() {
        XCTAssertFalse(ArchiveInvocation.finder.recordsManualJob)
        XCTAssertTrue(ArchiveInvocation.manual.recordsManualJob)
    }

    func testTerminalProgressIgnoresLateUpdates() {
        var success = FinderArchiveProgressState(fileName: "good.zip")
        success.receive(.succeeded)
        success.receive(.failed(.tool))
        XCTAssertEqual(success.phase, .succeeded)

        var failure = FinderArchiveProgressState(fileName: "broken.zip")
        failure.receive(.failed(.tool))
        failure.receive(.extracting)
        XCTAssertEqual(failure.phase, .failed(.tool))
    }
}
