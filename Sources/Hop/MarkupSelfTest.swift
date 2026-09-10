import AppKit
import CoreImage
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
                        ink: MarkupInk(hex: "#FF453A", width: 5),
                        magnification: 4, createdAt: 1),
            MarkupShape(tool: .magnifier,
                        points: [MarkupPoint(x: 180, y: 430), MarkupPoint(x: 340, y: 590)],
                        ink: MarkupInk(hex: "#0A84FF", width: 4), createdAt: 2),
        ])

        let view = MarkupCanvas(surface: surface,
                                background: Image(decorative: base, scale: 1),
                                baked: true,
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
        let lenses: [(name: String, centre: (Int, Int), radius: Int)] = [
            ("first lens", (420, 590), 90),
            ("second lens", (260, 510), 80),
        ]
        for lens in lenses {
            // The rim is glass: no colour of its own, so it is looked for as a
            // change against the plain frame along the radius.
            var best = (-999, -999, -999)
            var near = false
            for step in -8...2 {
                let x = lens.centre.0 + lens.radius + step
                let probe = drawn.at(x, lens.centre.1)
                if probe != plainFrame.at(x, lens.centre.1) {
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

        func painted(_ marks: [MarkupShape]) -> Pixels? {
            let held = MarkupSurface()
            held.load(marks)
            let renderer = ImageRenderer(content: MarkupCanvas(surface: held,
                                                               background: Image(decorative: base, scale: 1),
                                                               baked: true, scale: 1, chrome: false)
                .frame(width: 1200, height: 750))
            renderer.scale = 1
            return renderer.cgImage.flatMap { Pixels($0) }
        }
        guard let marked = painted([stroke, lensOnStroke]), let clean = painted([lensOnStroke]) else {
            print("canvas: the lens over a marker did not render")
            return 1
        }
        let seen = marked.apart(from: clean, strokeUnderGlass, 16)
        print("canvas: a marker under a lens changes its middle by \(seen)")
        if seen < 3000 {
            print("canvas: the lens does NOT show the marker under it")
            failures += 1
        }

        // SPEC: docs/spec.md — another tool ends the edit in progress.
        surface.tool = .select
        surface.begin(at: MarkupPoint(x: 300, y: 190))
        surface.finish()
        if surface.selected == nil {
            print("canvas: the select tool took nothing")
            failures += 1
        }
        surface.tool = .rectangle
        if surface.selected != nil {
            print("canvas: a mark stayed in hand after another tool was taken")
            failures += 1
        } else {
            print("canvas: taking a tool let the previous mark go")
        }

        // SPEC: docs/spec.md — each monitor keeps its own marks.
        let screens = MarkupSurface()
        screens.load([MarkupShape(tool: .rectangle,
                                  points: [MarkupPoint(x: 100, y: 100), MarkupPoint(x: 300, y: 250)],
                                  ink: MarkupInk(hex: "#FF453A", width: 4), display: 1, createdAt: 0)])
        screens.tool = .select
        screens.begin(at: MarkupPoint(x: 200, y: 175), on: 2)
        screens.finish()
        let across = screens.selected != nil
        screens.begin(at: MarkupPoint(x: 200, y: 175), on: 1)
        screens.finish()
        let home = screens.selected != nil
        screens.tool = .steps
        for display in [UInt32(1), 2] {
            screens.begin(at: MarkupPoint(x: 600, y: 400), on: display)
            screens.finish()
        }
        let counts = screens.shapes.filter { $0.tool == .steps }.map { "\($0.display ?? 0):\($0.step ?? 0)" }
        print("canvas: a mark on monitor 1 taken from monitor 2: \(across), from 1: \(home); steps \(counts)")
        if across {
            print("canvas: the select tool reaches a mark on ANOTHER monitor")
            failures += 1
        }
        if !home {
            print("canvas: the select tool took nothing on the mark's own monitor")
            failures += 1
        }
        if counts != ["1:1", "2:1"] {
            print("canvas: the monitors share ONE step count")
            failures += 1
        }
        return failures == 0 ? 0 : 1
    }

    /// The canvas as the DRAWING LAYER draws it, once per blur setting.
    /// SPEC: docs/spec.md — the loupe and the blur over the live screen.
    @MainActor
    static func live(to directory: String) -> Int32 {
        guard let base = sampleFrame(width: 1200, height: 750) else {
            print("live: could not build the sample frame")
            return 1
        }
        let source = Image(decorative: base, scale: 1)
        let ink = MarkupInk(hex: "#FF453A", width: 4)

        func region(_ settings: MarkupBlur, at rect: CGRect = CGRect(x: 110, y: 440,
                                                                    width: 510, height: 160))
        -> MarkupShape {
            var shape = MarkupShape(tool: .blur,
                                    points: [MarkupPoint(x: rect.minX, y: rect.minY),
                                             MarkupPoint(x: rect.maxX, y: rect.maxY)],
                                    ink: ink, createdAt: 0)
            shape.blur = settings
            return shape
        }
        let second = CGRect(x: 100, y: 55, width: 430, height: 90)
        let lens = MarkupShape(tool: .magnifier,
                               points: [MarkupPoint(x: 200, y: 460), MarkupPoint(x: 340, y: 600)],
                               ink: MarkupInk(hex: "#FFFFFF", width: 5),
                               magnification: 3, createdAt: 1)

        func shot(_ shapes: [MarkupShape], _ name: String, blind: Bool = false,
                  on display: UInt32? = nil) -> Pixels? {
            let surface = MarkupSurface()
            surface.load(shapes)
            var tiles: [Int: Image] = [:]
            for shape in shapes where shape.blur?.style == .pixels {
                guard let strength = shape.blur?.strength,
                      let cut = MarkupRender.tiled(CIImage(cgImage: base),
                                                   side: MarkupBlur.mosaic(forStrength: strength))
                else { continue }
                tiles[strength] = Image(decorative: cut, scale: 1)
            }
            let view = MarkupCanvas(surface: surface, background: nil,
                                    source: blind ? nil : source, mosaics: tiles,
                                    scale: 1, display: display, chrome: false)
                .frame(width: 1200, height: 750)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let picture = renderer.cgImage else { return nil }
            do {
                try MarkupExport.write(picture,
                                       to: URL(fileURLWithPath: directory + "/" + name + ".png"),
                                       format: "png")
            } catch {
                print("live: \(name).png did not write — \(error.localizedDescription)")
                return nil
            }
            return Pixels(picture)
        }

        let bald = MarkupShape(tool: .blur,
                               points: [MarkupPoint(x: 110, y: 440), MarkupPoint(x: 620, y: 600)],
                               ink: ink, createdAt: 0)

        let smear = MarkupBlur(mode: .inside, shape: .rectangle, style: .blur, strength: 9, dim: 0)
        var mosaic = smear; mosaic.style = .pixels
        var out = smear; out.mode = .around; out.dim = 4
        var round = out; round.shape = .oval
        var strokeOnTwo = stroke; strokeOnTwo.display = 2

        guard let plain = Pixels(base),
              let blurred = shot([region(smear)], "live-blur"),
              let magnified = shot([region(smear), lens], "live-blur-loupe"),
              let tiled = shot([region(mosaic)], "live-pixels"),
              let around = shot([region(out)], "live-around"),
              let blind = shot([region(smear)], "live-no-frame", blind: true),
              let blindOut = shot([region(out)], "live-no-frame-out", blind: true),
              let mixed = shot([region(smear), region(mosaic, at: second)], "live-mixed"),
              let alike = shot([region(smear), region(smear, at: second)], "live-mixed-plain"),
              let oval = shot([region(round)], "live-around-oval"),
              let naked = shot([bald], "live-no-settings"),
              let nakedLens = shot([bald, lens], "live-no-settings-loupe"),
              let blindLens = shot([lens], "live-no-frame-loupe", blind: true),
              let inked = shot([stroke, lensOnStroke], "live-marker-loupe"),
              let uninked = shot([lensOnStroke], "live-loupe"),
              let away = shot([strokeOnTwo], "live-other-monitor", on: 1),
              let own = shot([strokeOnTwo], "live-own-monitor", on: 2),
              let bare = shot([], "live-bare") else {
            print("live: nothing rendered")
            return 1
        }

        let covered = (270, 530), radius = 70
        let glass = 55
        let corner = (130, 455), nook = 16
        let neighbour = (250, 100), span = 30
        let outside = (230, 90), reach = 40

        var failures = 0
        func expect(_ ok: Bool, _ complaint: String) {
            guard !ok else { return }
            print("live: \(complaint)")
            failures += 1
        }

        let clear = plain.detail(covered, radius)
        print("live: the frame itself carries \(clear) detail where the blur goes")

        let hidden = blurred.detail(covered, radius)
        print("live: blur leaves \(hidden), under the loupe \(magnified.detail(covered, radius))")
        expect(hidden * 3 < clear, "the blur does NOT hide what it covers")
        expect(magnified.detail(covered, radius) < max(hidden, 20) * 2,
               "the loupe SHOWS what the blur hides")

        print("live: dots leave \(tiled.detail(covered, radius)), "
              + "\(blurred.apart(from: tiled, covered, radius)) apart from blur")
        expect(tiled.detail(covered, radius) * 2 < clear, "the mosaic does NOT hide what it covers")
        expect(blurred.apart(from: tiled, covered, radius) > 200,
               "dots and blur come out the SAME picture")

        print("live: out touched the region by \(around.apart(from: bare, covered, radius)), "
              + "leaves \(around.detail(outside, reach)) outside "
              + "of \(plain.detail(outside, reach))")
        expect(around.apart(from: bare, covered, radius) < 200,
               "out smeared the region it should keep")
        expect(around.detail(outside, reach) * 3 < plain.detail(outside, reach),
               "out does NOT hide what lies beyond the region")
        expect(around.opacity(outside, reach) > 24000,
               "out left the canvas beyond the region UNPAINTED")
        print("live: the oval cut leaves the box's corner "
              + "\(oval.apart(from: bare, corner, nook)) from bare, the rectangle "
              + "\(around.apart(from: bare, corner, nook))")
        expect(oval.opacity(corner, nook) > 1200, "an OVAL region was cut as a rectangle")
        expect(around.opacity(corner, nook) < 1200, "a RECTANGLE region was cut as an oval")

        print("live: mixed styles differ by \(mixed.apart(from: alike, neighbour, span)) "
              + "where they differ, \(mixed.apart(from: alike, covered, radius)) where they do not")
        expect(mixed.apart(from: alike, neighbour, span) > 200,
               "dots asked for beside a blur came out a BLUR")
        expect(mixed.apart(from: alike, covered, radius) < 200,
               "a blur beside dots came out DOTTED")

        print("live: with no frame the region reads \(blind.opacity(covered, radius)) solid, "
              + "\(blind.brightness(covered, radius)) light; out covers "
              + "\(blindOut.opacity(outside, reach)) beyond it")
        expect(blind.opacity(covered, radius) > 24000, "with no frame the blur hides NOTHING")
        expect(blind.brightness(covered, radius) < 40, "the plate is not BLACK")
        expect(blindOut.opacity(outside, reach) > 24000,
               "with no frame out leaves the screen OPEN beyond the region")

        print("live: with no settings the region reads \(naked.brightness(covered, radius)) light, "
              + "under the loupe \(nakedLens.brightness(covered, radius)); "
              + "a loupe with no frame reads \(blindLens.brightness(covered, glass))")
        expect(naked.opacity(covered, radius) > 24000, "a blur with no settings hides NOTHING")
        expect(naked.brightness(covered, radius) < 40, "the plate is not BLACK")
        expect(nakedLens.brightness(covered, radius) < 40,
               "the loupe SHOWS what a blur with no settings could not hide")
        expect(blindLens.opacity(covered, glass) > 14000,
               "a loupe with no frame to read draws NOTHING at all")
        expect(blindLens.brightness(covered, glass) < 40, "the empty lens is not BLACK")

        let seen = inked.apart(from: uninked, strokeUnderGlass, 16)
        print("live: a marker under a lens changes its middle by \(seen)")
        expect(seen >= 3000, "the lens does NOT show the marker under it")

        let there = own.apart(from: bare, strokeUnderGlass, 16)
        let elsewhere = away.apart(from: bare, strokeUnderGlass, 16)
        print("live: a stroke on monitor 2 reads \(there) there, \(elsewhere) on monitor 1")
        expect(there >= 3000, "a stroke is NOT drawn on its own monitor")
        expect(elsewhere < 200, "a stroke on one monitor is drawn on ANOTHER")

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

        /// How much there is to read inside a circle: the average step in brightness between neighbours.
        func detail(_ centre: (Int, Int), _ radius: Int) -> Int {
            walk(centre, radius) { x, y in
                let here = at(x, y), next = at(x + 1, y)
                guard next.0 >= 0 else { return 0 }
                return abs(here.0 - next.0) + abs(here.1 - next.1) + abs(here.2 - next.2)
            }
        }

        /// How far apart two renders of the same scene are inside a circle.
        func apart(from other: Pixels, _ centre: (Int, Int), _ radius: Int) -> Int {
            walk(centre, radius) { x, y in
                let here = at(x, y), there = other.at(x, y)
                return abs(here.0 - there.0) + abs(here.1 - there.1) + abs(here.2 - there.2)
            }
        }

        /// How solid a circle is: what tells a plate from an open region.
        func opacity(_ centre: (Int, Int), _ radius: Int) -> Int {
            walk(centre, radius) { x, y in alpha(x, y) }
        }

        /// How light a circle is: a solid plate over a pale frame reads near 0.
        func brightness(_ centre: (Int, Int), _ radius: Int) -> Int {
            walk(centre, radius) { x, y in
                let here = at(x, y)
                return (here.0 + here.1 + here.2) / 3
            } / 100
        }

        private func walk(_ centre: (Int, Int), _ radius: Int,
                          _ read: (Int, Int) -> Int) -> Int {
            var sum = 0, counted = 0
            for y in (centre.1 - radius)...(centre.1 + radius) {
                for x in (centre.0 - radius)...(centre.0 + radius) {
                    let dx = Double(x - centre.0), dy = Double(y - centre.1)
                    guard (dx * dx + dy * dy).squareRoot() < Double(radius) - 10,
                          at(x, y).0 >= 0 else { continue }
                    sum += read(x, y)
                    counted += 1
                }
            }
            return counted == 0 ? 0 : sum * 100 / counted
        }

        func at(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            guard x >= 0, y >= 0, x < width, y < height else { return (-1, -1, -1) }
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }

        func alpha(_ x: Int, _ y: Int) -> Int {
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            return Int(bytes[(y * width + x) * 4 + 3])
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
        guard let marked = MarkupRender.compose(base: base, shapes: [stroke, lensOnStroke], scale: 1)
                .flatMap({ Pixels($0) }),
              let clean = MarkupRender.compose(base: base, shapes: [lensOnStroke], scale: 1)
                .flatMap({ Pixels($0) })
        else {
            print("markup: the lens over a marker did not render")
            return 1
        }
        let seen = marked.apart(from: clean, strokeUnderGlass, 16)
        print("markup: a marker under a lens changes its middle by \(seen)")
        guard seen >= 3000 else {
            print("markup: the lens in the file does NOT show the marker under it")
            return 1
        }
        return picture.width == Int(expected.x) ? 0 : 1
    }

    /// SPEC: docs/spec.md — the loupe magnifies the marks laid before it.
    private static let stroke = MarkupShape(
        tool: .marker, points: [MarkupPoint(x: 700, y: 180), MarkupPoint(x: 1000, y: 180)],
        ink: MarkupInk(hex: "#FFD60A", width: 26), createdAt: 0)
    private static let lensOnStroke = MarkupShape(
        tool: .magnifier, points: [MarkupPoint(x: 780, y: 110), MarkupPoint(x: 920, y: 250)],
        ink: MarkupInk(hex: "#FFFFFF", width: 5), createdAt: 1)
    private static let strokeUnderGlass = (850, 180)

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
