import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import HopCore

/// Puts the marks onto the picture at the source's own resolution.
///
/// The editor draws with SwiftUI for the screen; the export draws with Core
/// Graphics, because a picture scaled for a window and a picture saved to disk
/// are not the same pixels.
enum MarkupRender {
    static func shortened(_ from: CGPoint, _ to: CGPoint, by amount: CGFloat) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > amount else { return to }
        return CGPoint(x: to.x - dx / length * amount, y: to.y - dy / length * amount)
    }

    /// What blur and the loupe do to the PIXELS, with no mark drawn on top.
    /// The editor shows this under its own vector marks: those two tools change
    /// the picture rather than sit on it, and a dashed outline is not what they
    /// did.
    static func effects(base: CGImage, shapes: [MarkupShape], scale: Double) -> CGImage? {
        // The loupe is drawn by the canvas itself, live under the hand; only
        // the blur has to be baked in behind the marks.
        let lenses: [MarkupShape] = []
        let blurred = smeared(base: base, shapes: shapes, scale: scale)
        guard blurred != nil || !lenses.isEmpty else { return nil }

        let picture = blurred ?? base
        guard !lenses.isEmpty else { return picture }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: picture.width, height: picture.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return picture }

        context.draw(picture, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
        context.translateBy(x: 0, y: CGFloat(picture.height))
        context.scaleBy(x: 1, y: -1)
        for lens in lenses { magnify(lens, base: picture, scale: scale, in: context) }
        return context.makeImage() ?? picture
    }

    static func compose(base: CGImage, shapes: [MarkupShape], scale: Double) -> CGImage? {
        let width = base.width
        let height = base.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let blurred = smeared(base: base, shapes: shapes, scale: scale) ?? base
        context.draw(blurred, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Core Graphics counts up from the bottom; the marks were placed on a
        // view counting down from the top.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for shape in shapes where shape.tool != .blur {
            if shape.tool == .magnifier {
                magnify(shape, base: blurred, scale: scale, in: context)
                continue
            }
            draw(shape, scale: scale, in: context)
        }
        return context.makeImage()
    }

    /// The region under the frame, drawn back at twice the size inside it.
    private static func magnify(
        _ shape: MarkupShape, base: CGImage, scale: Double, in context: CGContext
    ) {
        let box = MarkupGeometry.boundingBox(shape.points)
        guard box.size.x > 8, box.size.y > 8 else { return }
        let drawn = CGRect(x: box.origin.x * scale, y: box.origin.y * scale,
                           width: box.size.x * scale, height: box.size.y * scale)
        // A circle, whatever shape the drag was: the biggest that fits.
        let side = min(drawn.width, drawn.height)
        let frame = CGRect(x: drawn.midX - side / 2, y: drawn.midY - side / 2,
                           width: side, height: side)
        // `cropping` measures from the image's top left, which is the same
        // corner the flipped context counts from — no conversion needed.
        let zoom = MarkupEditing.Zoom.of(shape)
        let source = CGRect(x: frame.midX - frame.width / (zoom * 2),
                            y: frame.midY - frame.height / (zoom * 2),
                            width: frame.width / zoom, height: frame.height / zoom)
        guard let piece = base.cropping(to: source) else { return }

        let round = CGPath(ellipseIn: frame, transform: nil)
        context.saveGState()
        context.addPath(round)
        context.clip()
        // Images draw bottom-up even in a flipped context, so the frame is
        // turned over once more before the piece lands in it.
        context.translateBy(x: frame.minX, y: frame.minY + frame.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(piece, in: CGRect(origin: .zero, size: frame.size))
        context.restoreGState()

        // Glass, not a drawn circle: a thick colourless rim, lit from the top
        // left, with a hairline inside and out to hold its edge.
        // A fixed rim in the picture's own points: a lens pulled bigger is a
        // bigger lens, not a thicker one.
        let rim = max(2, 4 * scale)
        context.setLineWidth(rim)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.45).cgColor)
        context.addPath(CGPath(ellipseIn: frame, transform: nil))
        context.strokePath()

        context.saveGState()
        context.setLineWidth(rim * 0.55)
        context.addPath(CGPath(ellipseIn: frame, transform: nil))
        context.replacePathWithStrokedPath()
        context.clip()
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let shine = CGGradient(colorsSpace: space,
                                  colors: [NSColor.white.withAlphaComponent(0.95).cgColor,
                                           NSColor.white.withAlphaComponent(0.1).cgColor] as CFArray,
                                  locations: [0, 1]) {
            context.drawLinearGradient(shine,
                                       start: CGPoint(x: frame.minX, y: frame.maxY),
                                       end: CGPoint(x: frame.maxX, y: frame.minY),
                                       options: [])
        }
        context.restoreGState()

        context.setLineWidth(1)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.addPath(CGPath(ellipseIn: frame.insetBy(dx: -rim / 2, dy: -rim / 2), transform: nil))
        context.strokePath()
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.2).cgColor)
        context.addPath(CGPath(ellipseIn: frame.insetBy(dx: rim / 2, dy: rim / 2), transform: nil))
        context.strokePath()
    }

    private static func smeared(base: CGImage, shapes: [MarkupShape], scale: Double) -> CGImage? {
        let regions = shapes.filter { $0.tool == .blur && $0.blur != nil }
        guard !regions.isEmpty else { return nil }

        var picture = CIImage(cgImage: base)
        let extent = picture.extent
        let ciContext = CIContext()

        for region in regions {
            guard let settings = region.blur else { continue }
            let box = pixelBox(region.points, scale: scale, height: extent.height)
            guard box.width > 1, box.height > 1 else { continue }

            let smudged: CIImage
            if settings.style == .pixels {
                let filter = CIFilter.pixellate()
                filter.inputImage = picture
                filter.scale = Float(max(4, Double(settings.strength) * 3 * scale))
                filter.center = CGPoint(x: box.midX, y: box.midY)
                smudged = filter.outputImage?.cropped(to: extent) ?? picture
            } else {
                let filter = CIFilter.gaussianBlur()
                filter.inputImage = picture.clampedToExtent()
                filter.radius = Float(Double(settings.strength) * 2.5 * scale)
                smudged = filter.outputImage?.cropped(to: extent) ?? picture
            }

            let mask = maskImage(for: region, box: box, extent: extent, mode: settings.mode)
            let blend = CIFilter.blendWithMask()
            blend.inputImage = smudged
            blend.backgroundImage = picture
            blend.maskImage = mask
            picture = blend.outputImage?.cropped(to: extent) ?? picture

            if settings.mode == .around, settings.dim > 0 {
                let shade = CIImage(color: CIColor(red: 0, green: 0, blue: 0,
                                                   alpha: Double(settings.dim) / 20)).cropped(to: extent)
                let overlay = CIFilter.blendWithMask()
                overlay.inputImage = shade.composited(over: picture)
                overlay.backgroundImage = picture
                overlay.maskImage = mask
                picture = overlay.outputImage?.cropped(to: extent) ?? picture
            }
        }
        return ciContext.createCGImage(picture, from: extent)
    }

    private static func maskImage(
        for region: MarkupShape, box: CGRect, extent: CGRect, mode: MarkupBlur.Mode
    ) -> CIImage {
        let inside = CIImage(color: .white).cropped(to: box)
        let outside = CIImage(color: .black).cropped(to: extent)
        let shaped = inside.composited(over: outside)
        guard mode == .around else { return shaped }
        let invert = CIFilter.colorInvert()
        invert.inputImage = shaped
        return invert.outputImage?.cropped(to: extent) ?? shaped
    }

    private static func pixelBox(_ points: [MarkupPoint], scale: Double, height: CGFloat) -> CGRect {
        let box = MarkupGeometry.boundingBox(points)
        let top = box.origin.y * scale
        return CGRect(x: box.origin.x * scale,
                      y: height - top - box.size.y * scale,
                      width: box.size.x * scale,
                      height: box.size.y * scale)
    }

    private static func draw(_ shape: MarkupShape, scale: Double, in context: CGContext) {
        let colour = NSColor(hex: shape.ink.hex)
        let points = shape.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        guard let first = points.first else { return }
        context.setLineWidth(shape.ink.width * scale)
        context.setStrokeColor(colour.cgColor)
        context.setFillColor(colour.cgColor)

        switch shape.tool {
        case .select:
            return
        case .pencil, .fadingInk:
            context.beginPath()
            context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            context.strokePath()

        case .marker:
            context.saveGState()
            context.setBlendMode(.multiply)
            context.setStrokeColor(colour.withAlphaComponent(0.45).cgColor)
            context.beginPath()
            context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            context.strokePath()
            context.restoreGState()

        case .line:
            guard points.count > 1 else { return }
            context.strokeLineSegments(between: [first, points[1]])

        case .arrow:
            guard points.count > 1 else { return }
            let head = MarkupGeometry.arrowHead(from: shape.points[0], to: shape.points[1],
                                                style: shape.arrow ?? .solid, width: shape.ink.width)
            let barbs = head.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
            // The shaft stops where the head begins: run it to the tip and its
            // round cap sticks out past the point.
            let stop = barbs.count == 3
                ? barbs[1]
                : Self.shortened(first, points[1], by: shape.ink.width * scale / 2)
            context.strokeLineSegments(between: [first, stop])
            if barbs.count == 3 {
                context.beginPath()
                context.move(to: barbs[0])
                context.addLine(to: points[1])
                context.addLine(to: barbs[2])
                context.addLine(to: barbs[1])
                context.closePath()
                context.fillPath()
            } else if barbs.count == 2 {
                context.strokeLineSegments(between: [barbs[0], points[1], barbs[1], points[1]])
            }

        case .rectangle:
            guard points.count > 1 else { return }
            context.stroke(rect(first, points[1]))

        case .oval:
            guard points.count > 1 else { return }
            context.strokeEllipse(in: rect(first, points[1]))

        case .steps:
            let radius = 17 * scale
            let circle = CGRect(x: first.x - radius, y: first.y - radius,
                                width: radius * 2, height: radius * 2)
            context.fillEllipse(in: circle)
            drawText("\(shape.step ?? 1)", at: CGPoint(x: circle.midX, y: circle.midY),
                     size: 19 * scale, colour: .white, centred: true, in: context)

        case .text:
            drawText(shape.text ?? "", at: first, size: shape.ink.width * scale,
                     colour: colour, centred: false, in: context)

        case .blur, .magnifier, .crop, .eraser:
            return
        }
    }

    private static func drawText(
        _ text: String, at point: CGPoint, size: CGFloat,
        colour: NSColor, centred: Bool, in context: CGContext
    ) {
        guard !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: colour,
        ]
        let line = NSAttributedString(string: text, attributes: attributes)
        let bounds = line.size()
        let origin = centred
            ? CGPoint(x: point.x - bounds.width / 2, y: point.y - bounds.height / 2)
            : point

        // The context is already flipped for the marks, so AppKit is told so:
        // asked for an unflipped one it would draw the glyphs mirrored.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        line.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}

extension NSColor {
    convenience init(hex: String) {
        guard let parts = ColorFormatting.components(hex) else {
            self.init(white: 1, alpha: 1)
            return
        }
        self.init(srgbRed: CGFloat(parts.r) / 255, green: CGFloat(parts.g) / 255,
                  blue: CGFloat(parts.b) / 255, alpha: 1)
    }
}
