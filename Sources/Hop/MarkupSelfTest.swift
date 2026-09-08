import AppKit
import HopCore
import SwiftUI

/// `Hop --markup-selftest <out.png>` runs a made-up frame through the whole
/// export path — marks, blur in both directions, dressing, watermark — and
/// writes the result. It is how the pipeline is re-checked without anybody
/// dragging a mouse.
enum MarkupSelfTest {
    /// The canvas as the editor draws it. SPEC: docs/spec.md
    @MainActor
    static func canvas(to path: String) -> Int32 {
        guard let base = sampleFrame(width: 1200, height: 750) else {
            print("canvas: could not build the sample frame")
            return 1
        }
        let surface = MarkupSurface()
        let ink = MarkupInk(hex: "#FF453A", width: 6)
        surface.load([
            MarkupShape(tool: .rectangle,
                        points: [MarkupPoint(x: 120, y: 120), MarkupPoint(x: 520, y: 260)],
                        ink: ink, createdAt: 0),
            MarkupShape(tool: .pencil,
                        points: (0..<30).map { MarkupPoint(x: 660 + Double($0) * 8,
                                                           y: 470 + sin(Double($0) / 3) * 30) },
                        ink: MarkupInk(hex: "#32D74B", width: 5), createdAt: 3),
            MarkupShape(tool: .pencil,
                        points: (0..<20).map { MarkupPoint(x: 200 + Double($0) * 6,
                                                           y: 500 + cos(Double($0) / 3) * 20) },
                        ink: MarkupInk(hex: "#FF9F0A", width: 4), createdAt: 4),
            MarkupShape(tool: .magnifier,
                        points: [MarkupPoint(x: 330, y: 500), MarkupPoint(x: 510, y: 680)],
                        ink: MarkupInk(hex: "#FF453A", width: 5), createdAt: 1),
            MarkupShape(tool: .magnifier,
                        points: [MarkupPoint(x: 180, y: 430), MarkupPoint(x: 340, y: 590)],
                        ink: MarkupInk(hex: "#0A84FF", width: 4), createdAt: 2),
        ])

        let view = MarkupCanvas(surface: surface,
                                background: Image(decorative: base, scale: 1),
                                scale: 1,
                                chrome: false)
            .frame(width: 1200, height: 750)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let picture = renderer.cgImage else {
            print("canvas: nothing rendered")
            return 1
        }
        do {
            try MarkupExport.write(picture, to: URL(fileURLWithPath: path), format: "png")
        } catch {
            print("canvas: \(error.localizedDescription)")
            return 1
        }
        print("canvas: \(picture.width)×\(picture.height) written to \(path)")

        guard let drawn = Pixels(picture), let plainFrame = Pixels(base) else {
            print("canvas: could not read the pixels back")
            return 1
        }
        var failures = 0
        var magnified = 0
        let lenses: [(name: String, centre: (Int, Int), radius: Int, rim: (Int, Int, Int))] = [
            ("red lens", (420, 590), 90, (255, 69, 58)),
            ("blue lens", (260, 510), 80, (10, 132, 255)),
        ]
        for lens in lenses {
            var best = (-999, -999, -999)
            var near = false
            for step in -6...6 {
                let probe = drawn.at(lens.centre.0 + lens.radius + step, lens.centre.1)
                if abs(probe.0 - lens.rim.0) < 25 && abs(probe.1 - lens.rim.1) < 25
                    && abs(probe.2 - lens.rim.2) < 25 {
                    near = true
                    best = probe
                    break
                }
                best = probe
            }
            print("canvas: \(lens.name) rim \(near ? "drawn" : "MISSING") \(best)")
            if !near { failures += 1 }

            var changed = 0
            var counted = 0
            for y in (lens.centre.1 - lens.radius + 4)...(lens.centre.1 + lens.radius - 4) {
                for x in (lens.centre.0 - lens.radius + 4)...(lens.centre.0 + lens.radius - 4) {
                    let dx = Double(x - lens.centre.0), dy = Double(y - lens.centre.1)
                    guard (dx * dx + dy * dy).squareRoot() < Double(lens.radius) - 6 else { continue }
                    counted += 1
                    if drawn.at(x, y) != plainFrame.at(x, y) { changed += 1 }
                }
            }
            let share = counted == 0 ? 0 : changed * 100 / counted
            print("canvas: \(lens.name) glass changed \(share)% of what it covers")
            magnified = max(magnified, share)
        }

        if magnified < 10 {
            print("canvas: NO lens magnified anything")
            failures += 1
        }
        return failures == 0 ? 0 : 1
    }

    /// Every pixel of an image, read once into a buffer of its own.
    /// WORKAROUND: sampling through `cropping` or a 1×1 context answers for the
    /// image as a whole, the same value wherever it is asked for.
    struct Pixels {
        let width: Int
        let height: Int
        private let bytes: [UInt8]

        init?(_ image: CGImage) {
            width = image.width
            height = image.height
            let side = image.width
            let tall = image.height
            var buffer = [UInt8](repeating: 0, count: side * tall * 4)
            var ok = false
            buffer.withUnsafeMutableBytes { raw in
                guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                      let context = CGContext(data: raw.baseAddress, width: side, height: tall,
                                              bitsPerComponent: 8, bytesPerRow: side * 4,
                                              space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return }
                context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: tall))
                ok = true
            }
            guard ok else { return nil }
            bytes = buffer
        }

        func at(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            guard x >= 0, y >= 0, x < width, y < height else { return (-1, -1, -1) }
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }
    }

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

        shapes.append(MarkupShape(tool: .magnifier,
                                  points: [MarkupPoint(x: 150, y: 48), MarkupPoint(x: 470, y: 168)],
                                  ink: MarkupInk(hex: "#FFFFFF", width: 5), createdAt: 7))

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
