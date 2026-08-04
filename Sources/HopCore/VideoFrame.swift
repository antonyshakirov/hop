import Foundation

/// Fitting a video into the frame a platform expects.
///
/// A social platform does not ask for a resolution, it asks for a SHAPE: a
/// reel is 9:16, a feed post 4:5 or square, a video 16:9. Converting into one
/// of those shapes is two decisions — how big the frame is, and what happens
/// to the picture when its own shape does not match. This works out both, in
/// plain numbers, with no video framework in sight.
public enum VideoFrame {
    /// The shapes worth naming, as width ÷ height.
    public enum Shape: String, CaseIterable, Sendable {
        case source          // whatever the video already is
        case vertical        // 9:16 — reels, stories, shorts
        case portrait        // 4:5 — the tallest a feed will show uncropped
        case square          // 1:1
        case landscape       // 16:9

        public var ratio: Double? {
            switch self {
            case .source: return nil
            case .vertical: return 9.0 / 16
            case .portrait: return 4.0 / 5
            case .square: return 1
            case .landscape: return 16.0 / 9
            }
        }
    }

    /// What happens to a picture whose shape does not match the frame.
    public enum Fit: String, CaseIterable, Sendable {
        case fill            // fill the frame, lose the edges
        case pad             // show all of it, leave the frame empty around it
        case blur            // show all of it, fill the rest with a blurred copy
    }

    /// The frame and where the picture sits inside it. Sizes are in pixels and
    /// even, because encoders refuse odd ones.
    public struct Layout: Equatable, Sendable {
        public let width: Double
        public let height: Double
        /// Uniform scale applied to the source picture.
        public let scale: Double
        /// Where the scaled picture's bottom-left corner goes inside the frame.
        /// Negative for a picture that overflows and gets cropped.
        public let offsetX: Double
        public let offsetY: Double

        public init(width: Double, height: Double, scale: Double, offsetX: Double, offsetY: Double) {
            self.width = width
            self.height = height
            self.scale = scale
            self.offsetX = offsetX
            self.offsetY = offsetY
        }

        /// True when the picture does not cover the frame, so something has to
        /// go in the space around it.
        public var hasEmptySpace: Bool { offsetX > 0.5 || offsetY > 0.5 }
    }

    /// Frame and placement for a source of `sourceWidth` × `sourceHeight`.
    ///
    /// `shortSide` is the resolution the user asked for, read as the frame's
    /// SHORT side (1080 means 1080×1920 for a reel and 1920×1080 for a
    /// landscape video), or nil to keep the source's own scale.
    ///
    /// Nothing is ever upscaled: a frame that would demand more pixels than the
    /// source has shrinks to what the source can fill. Returns nil when there
    /// is nothing to do — the source already IS this shape at this size.
    public static func layout(
        sourceWidth: Double, sourceHeight: Double, shape: Shape, shortSide: Double?, fit: Fit
    ) -> Layout? {
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        guard let ratio = shape.ratio else {
            return sourceLayout(sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                                shortSide: shortSide)
        }
        // the frame at the asked-for size, before the source has its say
        let side = shortSide ?? min(sourceWidth, sourceHeight)
        var frameWidth = ratio <= 1 ? side : side * ratio
        var frameHeight = ratio <= 1 ? side / ratio : side

        // how much the source has to be scaled to satisfy this fit
        var scale = fitScale(sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                             frameWidth: frameWidth, frameHeight: frameHeight, fit: fit)
        // never upscale: shrink the whole frame instead, keeping its shape
        if scale > 1 {
            frameWidth /= scale
            frameHeight /= scale
            scale = 1
        }
        let width = even(frameWidth)
        let height = even(frameHeight)
        // recompute against the rounded frame so the picture stays centred
        scale = fitScale(sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                         frameWidth: width, frameHeight: height, fit: fit)
        return Layout(
            width: width, height: height, scale: scale,
            offsetX: (width - sourceWidth * scale) / 2,
            offsetY: (height - sourceHeight * scale) / 2
        )
    }

    /// The old behaviour, kept whole: no reshaping, only a downscale to a short
    /// side. nil when the source is already at or under that size.
    private static func sourceLayout(
        sourceWidth: Double, sourceHeight: Double, shortSide: Double?
    ) -> Layout? {
        guard let shortSide else { return nil }
        let scale = shortSide / min(sourceWidth, sourceHeight)
        guard scale < 1 else { return nil }
        return Layout(
            width: even(sourceWidth * scale), height: even(sourceHeight * scale),
            scale: scale, offsetX: 0, offsetY: 0
        )
    }

    private static func fitScale(
        sourceWidth: Double, sourceHeight: Double,
        frameWidth: Double, frameHeight: Double, fit: Fit
    ) -> Double {
        let byWidth = frameWidth / sourceWidth
        let byHeight = frameHeight / sourceHeight
        // filling takes the larger scale and lets the excess fall outside;
        // the other two take the smaller and leave space to deal with
        return fit == .fill ? max(byWidth, byHeight) : min(byWidth, byHeight)
    }

    private static func even(_ value: Double) -> Double {
        max(2, (value / 2).rounded() * 2)
    }
}
