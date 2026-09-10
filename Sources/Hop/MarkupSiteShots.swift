import AppKit
import CoreGraphics
import HopCore

/// WORKAROUND: `MarkupCanvas` comes out of a headless render as a "missing
/// picture" glyph, so these two shots are composed in Core Graphics instead.
/// SPEC: docs/spec.md — "Photographing the two markup modules".
@MainActor
enum MarkupSiteShots {
    static func run(into directory: String) {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let width = 1120, height = 700
        guard let page = page(width: width, height: height) else {
            print("markup shots: the page would not draw"); exit(1)
        }
        let marks = marks(width: Double(width), height: Double(height))
        guard let marked = MarkupRender.compose(base: page, shapes: marks, scale: 1) else {
            print("markup shots: the marks would not draw"); exit(1)
        }

        var dressing = FrameDressing.standard
        dressing.isOn = true
        let editor = FrameDressingRenderer.dress(marked, with: dressing) ?? marked
        write(editor, to: url.appendingPathComponent("shot.png"))
        write(layer(over: marked), to: url.appendingPathComponent("annotate.png"))
        print("markup shots → \(url.path)")
        exit(0)
    }

    private static func page(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let w = Double(width), h = Double(height)
        func box(_ rect: CGRect, radius: Double, _ colour: (Double, Double, Double)) {
            context.setFillColor(red: colour.0, green: colour.1, blue: colour.2, alpha: 1)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius,
                                   cornerHeight: radius, transform: nil))
            context.fillPath()
        }

        box(CGRect(x: 0, y: 0, width: w, height: h), radius: 0, (0.97, 0.97, 0.96))
        box(CGRect(x: 0, y: h - 52, width: w, height: 52), radius: 0, (0.13, 0.15, 0.19))
        for (index, colour) in [(0.94, 0.35, 0.31), (0.96, 0.75, 0.25), (0.36, 0.78, 0.40)].enumerated() {
            context.setFillColor(red: colour.0, green: colour.1, blue: colour.2, alpha: 1)
            context.fillEllipse(in: CGRect(x: 22 + Double(index) * 24, y: h - 33, width: 13, height: 13))
        }
        box(CGRect(x: 60, y: h - 146, width: w * 0.46, height: 28), radius: 6, (0.20, 0.20, 0.22))

        var y = h - 208
        var line = 0
        while y > 150 {
            box(CGRect(x: 60, y: y, width: w * [0.72, 0.64, 0.68, 0.46][line % 4], height: 13),
                radius: 6, (0.76, 0.76, 0.75))
            y -= 38
            line += 1
        }
        box(CGRect(x: 60, y: 62, width: 214, height: 48), radius: 11, (0.16, 0.42, 0.92))
        box(CGRect(x: 98, y: 80, width: 138, height: 13), radius: 6, (0.93, 0.95, 0.99))
        return context.makeImage()
    }

    private static func marks(width: Double, height: Double) -> [MarkupShape] {
        let red = MarkupInk(hex: "#FF3B30", width: 5)
        return [
            MarkupShape(tool: .rectangle,
                        points: [MarkupPoint(x: width * 0.04, y: height * 0.16),
                                 MarkupPoint(x: width * 0.54, y: height * 0.24)],
                        ink: red, createdAt: 0),
            MarkupShape(tool: .arrow,
                        points: [MarkupPoint(x: width * 0.62, y: height * 0.70),
                                 MarkupPoint(x: width * 0.26, y: height * 0.88)],
                        ink: red, arrow: .triangle, createdAt: 1),
            MarkupShape(tool: .text,
                        points: [MarkupPoint(x: width * 0.63, y: height * 0.64)],
                        ink: MarkupInk(hex: "#FF3B30", width: 26),
                        text: L10n.t(.annotateStart, L10n.current), createdAt: 2),
        ]
    }

    private static func layer(over base: CGImage) -> CGImage {
        let w = Double(base.width), h = Double(base.height)
        guard let context = CGContext(
            data: nil, width: base.width, height: base.height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return base }
        context.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))

        let yellow = (1.0, 0.84, 0.04)
        context.setStrokeColor(red: yellow.0, green: yellow.1, blue: yellow.2, alpha: 0.72)
        context.setLineWidth(6)
        context.stroke(CGRect(x: 3, y: 3, width: w - 6, height: h - 6))
        return context.makeImage() ?? base
    }

    private static func write(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
