import XCTest
@testable import HopCore

final class VideoPlatformTests: XCTestCase {
    // MARK: - The frames the platforms ask for

    func testEveryPresetIs1080AcrossTheShortSide() {
        for platform in VideoPlatform.allCases {
            let frame = platform.frame
            XCTAssertEqual(min(frame.width, frame.height), 1080, "\(platform)")
        }
    }

    func testTheVerticalPresetsAreReelSized() {
        for platform in [VideoPlatform.reels, .tiktok, .shorts] {
            let frame = platform.frame
            XCTAssertEqual(frame.width, 1080, "\(platform)")
            XCTAssertEqual(frame.height, 1920, "\(platform)")
        }
    }

    func testTheFeedPresetIsTheTallestUncroppedPost() {
        let frame = VideoPlatform.feed.frame
        XCTAssertEqual(frame.width, 1080)
        XCTAssertEqual(frame.height, 1350)
    }

    func testTheYouTubePresetIsLandscape() {
        let frame = VideoPlatform.youtube.frame
        XCTAssertEqual(frame.width, 1920)
        XCTAssertEqual(frame.height, 1080)
    }

    // MARK: - The dial the preset lands on

    func testTheDialLandsBackOnThePlatformsBitrate() {
        // the round trip is the whole point: dial position in, bitrate out,
        // and it has to be the number the platform published
        for platform in VideoPlatform.allCases {
            for codec in VideoBitrate.Codec.allCases {
                let frame = platform.frame
                let rate = VideoBitrate.bitsPerSecond(
                    width: frame.width, height: frame.height,
                    fps: VideoPlatform.referenceFPS, codec: codec,
                    quality: Double(platform.dialPercent(codec: codec)) / 100)
                let drift = abs(Double(rate - platform.bitsPerSecond))
                    / Double(platform.bitsPerSecond)
                // the dial only stores whole percent, so it cannot land exactly
                XCTAssertLessThan(drift, 0.02, "\(platform) \(codec)")
            }
        }
    }

    func testEveryPresetSitsSomewhereOnTheDial() {
        // a preset pinned at 1 or 100 would mean the dial cannot express it
        for platform in VideoPlatform.allCases {
            for codec in VideoBitrate.Codec.allCases {
                let percent = platform.dialPercent(codec: codec)
                XCTAssertGreaterThan(percent, 1, "\(platform) \(codec)")
                XCTAssertLessThan(percent, 100, "\(platform) \(codec)")
            }
        }
    }

    func testTheSameWeightCostsHevcFewerBitsPerPixel() {
        // the target is the file's weight, so the leaner codec is asked to
        // spend MORE of its dial to arrive at the same megabits
        for platform in VideoPlatform.allCases {
            XCTAssertGreaterThan(platform.dialPercent(codec: .hevc),
                                 platform.dialPercent(codec: .h264), "\(platform)")
        }
    }

    // MARK: - Which button lights up

    func testAPresetRecognisesItsOwnSettings() {
        for platform in VideoPlatform.allCases {
            for codec in VideoBitrate.Codec.allCases {
                XCTAssertTrue(platform.matches(
                    shape: platform.shape, shortSide: platform.shortSide,
                    dialPercent: platform.dialPercent(codec: codec),
                    compressing: true, codec: codec), "\(platform) \(codec)")
            }
        }
    }

    func testTheTwinPresetsLightUpTogether() {
        // TikTok and Shorts want the same file; claiming otherwise would be
        // a distinction the encoder cannot make
        let percent = VideoPlatform.tiktok.dialPercent(codec: .hevc)
        XCTAssertTrue(VideoPlatform.shorts.matches(
            shape: .vertical, shortSide: 1080, dialPercent: percent,
            compressing: true, codec: .hevc))
    }

    func testAReelIsNotAFeedPost() {
        let percent = VideoPlatform.reels.dialPercent(codec: .hevc)
        XCTAssertFalse(VideoPlatform.feed.matches(
            shape: .vertical, shortSide: 1080, dialPercent: percent,
            compressing: true, codec: .hevc))
    }

    func testTheSameShapeAtAnotherSqueezeIsNotThePreset() {
        let percent = VideoPlatform.reels.dialPercent(codec: .hevc)
        XCTAssertFalse(VideoPlatform.reels.matches(
            shape: .vertical, shortSide: 1080, dialPercent: percent + 9,
            compressing: true, codec: .hevc))
    }

    func testWithCompressionOffNoPresetHolds() {
        // nothing controls the bitrate then, so the platform's number is
        // not what comes out
        let percent = VideoPlatform.reels.dialPercent(codec: .hevc)
        XCTAssertFalse(VideoPlatform.reels.matches(
            shape: .vertical, shortSide: 1080, dialPercent: percent,
            compressing: false, codec: .hevc))
    }

    func testKeepingTheSourceResolutionIsNotThePreset() {
        let percent = VideoPlatform.reels.dialPercent(codec: .hevc)
        XCTAssertFalse(VideoPlatform.reels.matches(
            shape: .vertical, shortSide: nil, dialPercent: percent,
            compressing: true, codec: .hevc))
    }
}
