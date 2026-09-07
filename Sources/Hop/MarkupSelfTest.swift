import AppKit
import HopCore

/// `Hop --markup-selftest <out.png>` runs a made-up frame through the whole
/// export path — marks, blur in both directions, dressing, watermark — and
/// writes the result. It is how the pipeline is re-checked without anybody
/// dragging a mouse.
enum MarkupSelfTest {
    static func run(to path: String) -> Int32 {
        guard let base = sampleFrame(width: 1200, height: 750) else {
            print("markup: could not build the sample frame")
            return 1
        }

        let ink = MarkupInk(hex: "#FF453A", width: 6)
        var shapes: [MarkupShape] = [
            MarkupShape(tool: .pencil,
                        points: (0..<40).map { MarkupPoint(x: 120 + Double($0) * 12,
                                                           y: 300 + sin(Double($0) / 4) * 40) },
                        ink: ink, createdAt: 0),
            MarkupShape(tool: .arrow,
                        points: [MarkupPoint(x: 900, y: 180), MarkupPoint(x: 640, y: 380)],
                        ink: ink, createdAt: 1),
            MarkupShape(tool: .rectangle,
                        points: [MarkupPoint(x: 120, y: 120), MarkupPoint(x: 520, y: 260)],
                        ink: ink, createdAt: 2),
            MarkupShape(tool: .steps, points: [MarkupPoint(x: 620, y: 150)],
                        ink: ink, step: 1, createdAt: 3),
            MarkupShape(tool: .marker,
                        points: (0..<20).map { MarkupPoint(x: 160 + Double($0) * 16, y: 520) },
                        ink: MarkupInk(hex: "#FFD60A", width: 26), createdAt: 4),
            MarkupShape(tool: .text, points: [MarkupPoint(x: 140, y: 620)],
                        ink: MarkupInk(hex: "#0A84FF", width: 34),
                        text: "markup", createdAt: 5),
        ]

        var inside = MarkupShape(tool: .blur,
                                 points: [MarkupPoint(x: 168, y: 476), MarkupPoint(x: 560, y: 512)],
                                 ink: ink, createdAt: 6)
        inside.blur = MarkupBlur(mode: .inside, shape: .rectangle, style: .blur, strength: 9, dim: 0)
        shapes.append(inside)

        let dressing = FrameDressing(isOn: true, background: .preset(0), padding: 8,
                                     corners: 6, shadow: 8, browserFrame: true,
                                     address: "hop.tools")
        let watermark = Watermark(isOn: true, text: "hop.tools", imageName: nil,
                                  opacity: 55, size: 4, spot: .bottomTrailing, tiled: false)

        guard let picture = MarkupExport.render(base: base, shapes: shapes, scale: 1,
                                                crop: nil, dressing: dressing, watermark: watermark)
        else {
            print("markup: the render came back empty")
            return 1
        }

        do {
            try MarkupExport.write(picture, to: URL(fileURLWithPath: path), format: "png")
        } catch {
            print("markup: could not write \(path)")
            return 1
        }

        let expected = FrameDressing.outputSize(
            frame: MarkupPoint(x: 1200, y: 750), dressing: dressing
        )
        print("markup: \(picture.width)×\(picture.height) written to \(path)")
        print("markup: dressing asked for \(Int(expected.x))×\(Int(expected.y))")
        return picture.width == Int(expected.x) ? 0 : 1
    }

    /// A frame with something to hide and something to point at.
    private static func sampleFrame(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.setFillColor(NSColor(hex: "#F4F2EE").cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let lines = [
            ("Order № 4821", 34.0, 640.0),
            ("phone  +7 913 448 20 71", 22.0, 250.0),
            ("mail  hidden@example.com", 22.0, 210.0),
        ]
        for (text, size, y) in lines {
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: NSColor(hex: "#16181D"),
            ]).draw(at: CGPoint(x: 120, y: y))
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
