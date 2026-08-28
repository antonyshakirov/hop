import Foundation

/// How hard to squeeze a video, and what that will weigh.
///
/// The system's export presets only offer "highest quality", which on ordinary
/// footage re-encodes to roughly the size it started at — the converter looked
/// like it was doing nothing because, size-wise, it very nearly was (Anton,
/// 2026-08-04). Deciding the bitrate ourselves gives the user a dial AND makes
/// the forecast arithmetic rather than a trial encode: bitrate times duration
/// IS the file size, to within a couple of percent.
public enum VideoBitrate {
    public enum Codec: String, CaseIterable, Sendable {
        case h264
        case hevc

        /// HEVC carries the same picture in about two thirds of the bits. The
        /// factor is deliberately conservative — the marketing number is a half,
        /// which holds on clean studio footage and not on a handheld clip.
        var factor: Double { self == .hevc ? 0.65 : 1 }
    }

    /// Bits spent on one pixel of one frame at the two ends of the dial. The
    /// low end is where a talking head still looks fine and a leafy pan does
    /// not; the high end is visually indistinguishable from the source on
    /// everything but hard motion.
    static let lowBitsPerPixel = 0.035
    static let highBitsPerPixel = 0.22

    /// The encoder's video bitrate for a frame of this size at this rate.
    /// `quality` runs 0…1 and is the dial the user turns.
    public static func bitsPerSecond(
        width: Double, height: Double, fps: Double, codec: Codec, quality: Double
    ) -> Int {
        guard width > 0, height > 0, fps > 0 else { return 0 }
        let level = min(max(quality, 0), 1)
        // squared so the dial spends its travel where the eye notices: the top
        // third of the range is where an encode stops shedding detail
        let bitsPerPixel = lowBitsPerPixel + (highBitsPerPixel - lowBitsPerPixel) * level * level
        let raw = width * height * fps * bitsPerPixel * codec.factor
        // floor: below this even a slideshow falls apart, and no dial position
        // should produce a file nobody can watch
        return Int(max(raw, 120_000))
    }

    /// Where the dial has to sit for a frame of this size to come out at a
    /// given bitrate — the inverse of `bitsPerSecond`, for when the target is
    /// known and the dial position is not (a platform preset states megabits,
    /// never a dial). Clamped to 0…1: a target the dial cannot reach comes
    /// back as the nearest end it can.
    public static func quality(
        forBitsPerSecond target: Int, width: Double, height: Double,
        fps: Double, codec: Codec
    ) -> Double {
        guard width > 0, height > 0, fps > 0, target > 0 else { return 0 }
        let bitsPerPixel = Double(target) / (width * height * fps * codec.factor)
        let span = (bitsPerPixel - lowBitsPerPixel) / (highBitsPerPixel - lowBitsPerPixel)
        return min(max(span, 0), 1).squareRoot()
    }

    /// The audio bitrate that goes with it. Speech survives 64 kbps and music
    /// does not, and a converter cannot tell them apart, so this stays modest
    /// and constant rather than clever.
    public static let audioBitsPerSecond = 128_000

    /// What the encode will weigh: the bitrates, the duration, and the roughly
    /// 2% a container spends on its own bookkeeping.
    public static func projectedBytes(
        seconds: Double, videoBitsPerSecond: Int, audioBitsPerSecond: Int = audioBitsPerSecond
    ) -> Int64 {
        guard seconds > 0 else { return 0 }
        let bits = Double(videoBitsPerSecond + audioBitsPerSecond) * seconds
        return Int64(bits / 8 * 1.02)
    }

    /// A re-encode that would come out heavier than the source is not a
    /// conversion anybody asked for: the honest forecast in that case is the
    /// original size, because that is what the converter will keep.
    public static func honestProjection(projected: Int64, original: Int64) -> Int64 {
        original > 0 && projected > original ? original : projected
    }
}
