import AVFoundation
import HopAudioEngine
import XCTest

final class SoundMicrophoneTapStartupTests: XCTestCase {
    private let mismatch = NSError(domain: "com.apple.coreaudio.avfaudio", code: -10868)
    private func format(_ rate: Double) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    }

    func testBluetoothNegotiationReinstallsTapAfterStoppingTheFailedAttempt() throws {
        var events: [String] = []
        var starts = 0
        try SoundMicrophoneTapStartup.start(readFormat: {
            self.format(starts == 0 ? 48000 : 24000)
        }, installTap: { events.append("install") }, removeTap: {
            events.append("remove")
        }, stop: { events.append("stop") }, start: {
            starts += 1; events.append("start")
            if starts == 1 { throw self.mismatch }
        })
        XCTAssertEqual(events, ["install", "start", "remove", "stop", "install", "start"])
    }

    func testAnUnchangedFormatDoesNotRetry() {
        var starts = 0, removed = 0, stopped = 0
        XCTAssertThrowsError(try SoundMicrophoneTapStartup.start(readFormat: { self.format(48000) },
            installTap: {}, removeTap: { removed += 1 }, stop: { stopped += 1 }, start: {
                starts += 1; throw self.mismatch
            }))
        XCTAssertEqual(starts, 1); XCTAssertEqual(removed, 1); XCTAssertEqual(stopped, 1)
    }

    func testAnUnrelatedFailureDoesNotRetryEvenIfTheFormatChanged() {
        var starts = 0
        let error = NSError(domain: "com.apple.coreaudio.avfaudio", code: -50)
        XCTAssertThrowsError(try SoundMicrophoneTapStartup.start(readFormat: {
            self.format(starts == 0 ? 48000 : 24000)
        }, installTap: {}, removeTap: {}, stop: {}, start: {
            starts += 1; throw error
        })) { XCTAssertEqual(($0 as NSError).code, -50) }
        XCTAssertEqual(starts, 1)
    }

    func testASecondFailureCleansUpAndNeverStartsAThirdAttempt() {
        var starts = 0, removed = 0, stopped = 0
        XCTAssertThrowsError(try SoundMicrophoneTapStartup.start(readFormat: {
            self.format(starts == 0 ? 48000 : 24000)
        }, installTap: {}, removeTap: { removed += 1 }, stop: { stopped += 1 }, start: {
            starts += 1; throw self.mismatch
        }))
        XCTAssertEqual(starts, 2); XCTAssertEqual(removed, 2); XCTAssertEqual(stopped, 2)
    }

    func testAStableSuccessfulStartKeepsItsTapAndDoesNotStop() throws {
        var starts = 0, installed = 0, removed = 0, stopped = 0
        try SoundMicrophoneTapStartup.start(readFormat: { self.format(24000) },
            installTap: { installed += 1 }, removeTap: { removed += 1 }, stop: { stopped += 1 },
            start: { starts += 1 })
        XCTAssertEqual(starts, 1); XCTAssertEqual(installed, 1)
        XCTAssertEqual(removed, 0); XCTAssertEqual(stopped, 0)
    }
}
