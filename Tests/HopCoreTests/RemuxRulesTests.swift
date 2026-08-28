import XCTest
@testable import HopCore

final class RemuxRulesTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    // MARK: - Which files need it

    func testTheTwoContainersTheSystemCannotOpenAreRepacked() {
        XCTAssertTrue(RemuxRules.needsRepacking(url("clip.mkv")))
        XCTAssertTrue(RemuxRules.needsRepacking(url("clip.webm")))
    }

    func testTheExtensionIsReadWithoutRegardToCase() {
        XCTAssertTrue(RemuxRules.needsRepacking(url("CLIP.MKV")))
    }

    func testWhatTheSystemAlreadyReadsIsLeftAlone() {
        for name in ["clip.mp4", "clip.mov", "clip.m4v", "clip.avi", "photo.png"] {
            XCTAssertFalse(RemuxRules.needsRepacking(url(name)), name)
        }
    }

    // MARK: - What MP4 will carry

    func testAnOrdinaryMkvRepacks() {
        XCTAssertTrue(RemuxRules.canRepack(videoCodec: "h264", audioCodec: "aac"))
        XCTAssertTrue(RemuxRules.canRepack(videoCodec: "hevc", audioCodec: "ac3"))
        XCTAssertTrue(RemuxRules.canRepack(videoCodec: "av1", audioCodec: "opus"))
    }

    func testTheClassicWebmPairingCannot() {
        // vp8 + vorbis is what a webm usually is, and MP4 holds neither
        XCTAssertFalse(RemuxRules.canRepack(videoCodec: "vp8", audioCodec: "vorbis"))
        XCTAssertFalse(RemuxRules.canRepack(videoCodec: "h264", audioCodec: "vorbis"))
    }

    func testASilentFileIsJudgedOnItsPictureAlone() {
        XCTAssertTrue(RemuxRules.canRepack(videoCodec: "h264", audioCodec: nil))
        XCTAssertFalse(RemuxRules.canRepack(videoCodec: "vp8", audioCodec: nil))
    }

    func testAFileWithNoTracksAtAllIsNotRepackable() {
        XCTAssertFalse(RemuxRules.canRepack(videoCodec: nil, audioCodec: nil))
    }

    func testCodecNamesAreReadWithoutRegardToCase() {
        XCTAssertTrue(RemuxRules.canRepack(videoCodec: "H264", audioCodec: "AAC"))
    }

    // MARK: - The helper's arguments

    func testTheArgumentsCopyRatherThanEncode() {
        let args = RemuxRules.arguments(input: url("in.mkv"), output: url("out.mp4"))
        XCTAssertTrue(args.contains("copy"))
        XCTAssertFalse(args.contains { $0.hasPrefix("libx") }, "a repack never encodes")
        XCTAssertEqual(args.last, "/tmp/out.mp4")
    }

    func testAudioIsOptionalAndSubtitlesAreDropped() {
        let args = RemuxRules.arguments(input: url("in.mkv"), output: url("out.mp4"))
        XCTAssertTrue(args.contains("0:a:0?"), "a silent recording must not fail")
        XCTAssertTrue(args.contains("-sn"))
        XCTAssertTrue(args.contains("-dn"))
    }

    func testTheHelperIsNeverLeftWaitingOnInput() {
        let args = RemuxRules.arguments(input: url("in.mkv"), output: url("out.mp4"))
        // without these a prompt (overwrite? stdin?) would hang the job forever
        XCTAssertTrue(args.contains("-nostdin"))
        XCTAssertTrue(args.contains("-y"))
    }

    // MARK: - Reading the failure

    func testACodecLimitIsRecognisedAsOne() {
        XCTAssertTrue(RemuxRules.isCodecRefusal(
            "[mp4 @ 0x1] Could not find tag for codec vorbis in stream #1"))
    }

    func testABrokenFileIsNotMistakenForACodecLimit() {
        XCTAssertFalse(RemuxRules.isCodecRefusal("in.mkv: Invalid data found when processing input"))
        XCTAssertFalse(RemuxRules.isCodecRefusal(""))
    }

    // MARK: - Where the repack lands

    func testTheTemporaryKeepsTheSourceNameAndTakesMp4() {
        let out = RemuxRules.temporaryOutput(for: url("holiday.mkv"),
                                             in: URL(fileURLWithPath: "/tmp/staging"),
                                             token: "abc")
        XCTAssertEqual(out.pathExtension, "mp4")
        XCTAssertTrue(out.lastPathComponent.contains("holiday"))
        XCTAssertTrue(out.lastPathComponent.contains("abc"))
    }
}
