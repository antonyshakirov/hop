import AppKit
import HopCore

/// Draws the background, the air around the frame, its rounded corners, the
/// shadow and the browser bar. SPEC: the "Frame dressing" section of the design.
enum FrameDressingRenderer {
    /// Six backgrounds that read on a landing page without shouting.
    static let presets: [(NSColor, NSColor)] = [
        (NSColor(hex: "#6E6BF2"), NSColor(hex: "#3C2C8C")),
        (NSColor(hex: "#F26BA6"), NSColor(hex: "#8C2C5C")),
        (NSColor(hex: "#5AC8F5"), NSColor(hex: "#1C5C8C")),
        (NSColor(hex: "#5CD98C"), NSColor(hex: "#1C6C4C")),
        (NSColor(hex: "#2C2C2E"), NSColor(hex: "#101012")),
        (NSColor(hex: "#F2F0EB"), NSColor(hex: "#D8D4CC")),
    ]

    static func dress(_ base: CGImage, with dressing: FrameDressing) -> CGImage? {
        guard dressing.isOn else { return base }

        let frame = MarkupPoint(x: Double(base.width), y: Double(base.height))
        let size = FrameDressing.outputSize(frame: frame, dressing: dressing)
        let origin = FrameDressing.frameOrigin(frame: frame, dressing: dressing)
        let bar = dressing.browserFrame ? FrameDressing.barHeight(frame: frame) : 0
        let radius = FrameDressing.cornerRadius(frame: frame, dressing: dressing)
        let shadow = FrameDressing.shadowRadius(frame: frame, dressing: dressing)

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.x), height: Int(size.y),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        paintBackground(dressing.background, in: context, size: size)

        // The frame plus its bar, in Core Graphics' bottom-up coordinates.
        let card = CGRect(x: origin.x, y: origin.y - bar,
                          width: frame.x, height: frame.y + bar)
        let rounded = CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil)

        if shadow > 0 {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -shadow / 3), blur: shadow,
                              color: NSColor.black.withAlphaComponent(0.42).cgColor)
            context.addPath(rounded)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            context.restoreGState()
        }

        context.saveGState()
        context.addPath(rounded)
        context.clip()
        if bar > 0 {
            drawBrowserBar(dressing, in: context, card: card, bar: bar)
        }
        context.draw(base, in: CGRect(x: origin.x, y: origin.y - bar + bar,
                                      width: frame.x, height: frame.y))
        context.restoreGState()

        return context.makeImage()
    }

    private static func paintBackground(
        _ background: FrameDressing.Background, in context: CGContext, size: MarkupPoint
    ) {
        let bounds = CGRect(x: 0, y: 0, width: size.x, height: size.y)
        switch background {
        case .preset(let index):
            let pair = presets[max(0, min(presets.count - 1, index))]
            gradient(from: pair.0, to: pair.1, in: context, bounds: bounds)
        case .colour(let hex):
            context.setFillColor(NSColor(hex: hex).cgColor)
            context.fill(bounds)
        case .gradient(let from, let to):
            gradient(from: NSColor(hex: from), to: NSColor(hex: to), in: context, bounds: bounds)
        }
    }

    private static func gradient(from: NSColor, to: NSColor, in context: CGContext, bounds: CGRect) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ramp = CGGradient(colorsSpace: space,
                                    colors: [from.cgColor, to.cgColor] as CFArray,
                                    locations: [0, 1])
        else { return }
        context.drawLinearGradient(ramp,
                                   start: CGPoint(x: bounds.minX, y: bounds.maxY),
                                   end: CGPoint(x: bounds.maxX, y: bounds.minY),
                                   options: [])
    }

    private static func drawBrowserBar(
        _ dressing: FrameDressing, in context: CGContext, card: CGRect, bar: CGFloat
    ) {
        let strip = CGRect(x: card.minX, y: card.maxY - bar, width: card.width, height: bar)
        context.setFillColor(NSColor(hex: "#2A2A2C").cgColor)
        context.fill(strip)

        let dot = bar * 0.28
        let colours = [NSColor(hex: "#FF5F57"), NSColor(hex: "#FEBC2E"), NSColor(hex: "#28C840")]
        for (index, colour) in colours.enumerated() {
            context.setFillColor(colour.cgColor)
            context.fillEllipse(in: CGRect(x: strip.minX + bar * 0.5 + CGFloat(index) * dot * 1.9,
                                           y: strip.midY - dot / 2, width: dot, height: dot))
        }

        guard !dressing.address.isEmpty else { return }
        let field = CGRect(x: strip.minX + bar * 2.4, y: strip.minY + bar * 0.22,
                           width: strip.width - bar * 3.4, height: bar * 0.56)
        context.setFillColor(NSColor(hex: "#1C1C1E").cgColor)
        context.fill(CGPath(roundedRect: field, cornerWidth: field.height / 2,
                            cornerHeight: field.height / 2, transform: nil).boundingBox)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let text = NSAttributedString(string: dressing.address, attributes: [
            .font: NSFont.systemFont(ofSize: bar * 0.34),
            .foregroundColor: NSColor.white.withAlphaComponent(0.72),
        ])
        text.draw(at: CGPoint(x: field.minX + bar * 0.4, y: field.midY - bar * 0.2))
        NSGraphicsContext.restoreGraphicsState()
    }
}
