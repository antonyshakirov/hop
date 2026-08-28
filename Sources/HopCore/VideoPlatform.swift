import Foundation

/// The frame a platform expects an upload to arrive in.
///
/// The shape row already says 9:16, and a person about to post a reel is not
/// thinking in ratios — they are thinking "this goes to Instagram". A platform
/// button is that thought: it sets the shape, the resolution and how hard to
/// squeeze, all three at once, to what the platform itself publishes as its
/// recommendation. Nothing here is enforced by the platform; these are the
/// numbers their own upload guides give for 1080p at 30 fps, and a file that
/// lands on them is one the platform will not have to re-encode twice.
public enum VideoPlatform: String, CaseIterable, Sendable {
    case reels      // Instagram reels and stories
    case feed       // Instagram feed — the tallest post that shows uncropped
    case tiktok
    case shorts     // YouTube Shorts
    case youtube

    /// The frame rate the platforms quote their bitrates at. A 60 fps source
    /// keeps its own rate; the dial derived here is simply the position that
    /// lands on the recommendation for the ordinary case.
    public static let referenceFPS: Double = 30

    public var shape: VideoFrame.Shape {
        switch self {
        case .reels, .tiktok, .shorts: return .vertical
        case .feed: return .portrait
        case .youtube: return .landscape
        }
    }

    /// Every one of them asks for 1080 across the short side — the shape is
    /// what differs, not the pixel count.
    public var shortSide: Double { 1080 }

    /// The video bitrate the platform recommends for its own frame at 30 fps.
    /// Meta's guides sit at 5 Mbps for both the reel and the feed post;
    /// YouTube's 1080p SDR figure is 8 Mbps and Shorts inherits it; TikTok
    /// quotes a range whose sensible middle is the same 8.
    public var bitsPerSecond: Int {
        switch self {
        case .reels, .feed: return 5_000_000
        case .tiktok, .shorts, .youtube: return 8_000_000
        }
    }

    /// The frame this preset produces, in pixels.
    public var frame: (width: Double, height: Double) {
        guard let ratio = shape.ratio else { return (shortSide, shortSide) }
        return ratio <= 1
            ? (shortSide, shortSide / ratio)
            : (shortSide * ratio, shortSide)
    }

    /// Where the compression dial has to sit for this codec to hit the
    /// platform's bitrate. The TARGET IS THE WEIGHT, not the codec's own
    /// quality: HEVC carries the same picture in fewer bits, so asking it for
    /// the same bitrate buys a better picture at the size the platform wanted.
    /// Returned as the whole percent the dial actually stores.
    public func dialPercent(codec: VideoBitrate.Codec) -> Int {
        let size = frame
        let quality = VideoBitrate.quality(
            forBitsPerSecond: bitsPerSecond,
            width: size.width, height: size.height,
            fps: Self.referenceFPS, codec: codec)
        return Int((quality * 100).rounded())
    }

    /// Whether the current settings are already what this preset asks for —
    /// which buttons to light up. Everything has to agree: a reel-shaped 1080p
    /// video squeezed by an unrelated amount is not "for Instagram", it just
    /// looks like it.
    ///
    /// More than one can be lit at once, and that is the truth rather than a
    /// clash: TikTok and Shorts ask for the same frame at the same bitrate, so
    /// a file made for one IS a file made for the other.
    public func matches(
        shape: VideoFrame.Shape, shortSide: Double?, dialPercent: Int,
        compressing: Bool, codec: VideoBitrate.Codec
    ) -> Bool {
        compressing && shortSide == self.shortSide && shape == self.shape
            && self.dialPercent(codec: codec) == dialPercent
    }
}
