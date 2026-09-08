import AppKit
import HopCore

/// Stamps the mark over the finished picture: the user's own text, or an image
/// copied into Hop's support folder when it was chosen.
enum WatermarkRenderer {
    static func stamp(_ watermark: Watermark, on base: CGImage) -> CGImage? {
        guard watermark.hasSomethingToStamp else { return base }

        let frame = MarkupPoint(x: Double(base.width), y: Double(base.height))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: base.width, height: base.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        context.setAlpha(CGFloat(watermark.opacity) / 100)

        let height = Watermark.height(in: frame, watermark: watermark)
        guard let mark = markImage(watermark, height: height) else { return base }
        let size = MarkupPoint(x: Double(mark.width) * height / Double(mark.height), y: height)
        let inset = min(frame.x, frame.y) * 0.03

        if watermark.tiled {
            let step = Watermark.tileStep(of: size, spread: watermark.spread)
            // A slanted tile has to start outside the frame, or the corners it
            // rotates away from come out bare.
            let reach = watermark.slant == 0 ? 0.0 : max(size.x, size.y) + max(frame.x, frame.y) * 0.2
            var y = -reach
            while y < frame.y + reach {
                var x = -reach
                while x < frame.x + reach {
                    place(mark, at: CGRect(x: x, y: y, width: size.x, height: size.y),
                          slant: watermark.slant, in: context)
                    x += step.x
                }
                y += step.y
            }
        } else {
            let spot = Watermark.origin(of: size, in: frame, spot: watermark.spot, inset: inset)
            // The spot is named from the top; Core Graphics counts from below.
            place(mark, at: CGRect(x: spot.x, y: frame.y - spot.y - size.y,
                                   width: size.x, height: size.y),
                  slant: watermark.slant, in: context)
        }
        return context.makeImage()
    }

    private static func place(
        _ mark: CGImage, at box: CGRect, slant: Int, in context: CGContext
    ) {
        guard slant != 0 else {
            context.draw(mark, in: box)
            return
        }
        context.saveGState()
        context.translateBy(x: box.midX, y: box.midY)
        context.rotate(by: CGFloat(Double(slant) * .pi / 180))
        context.draw(mark, in: CGRect(x: -box.width / 2, y: -box.height / 2,
                                      width: box.width, height: box.height))
        context.restoreGState()
    }

    /// Where an image watermark is kept: a copy of its own, so a file moved or
    /// deleted later cannot silently empty the mark.
    static func store(imageAt url: URL, called stem: String = "watermark") -> String? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }

        let folder = support.appendingPathComponent("Hop", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(stem).\(url.pathExtension.isEmpty ? "png" : url.pathExtension)"
        let destination = folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return name
        } catch {
            return nil
        }
    }

    static func storedImageURL(_ name: String) -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) else { return nil }
        return support.appendingPathComponent("Hop", isDirectory: true).appendingPathComponent(name)
    }

    private static func markImage(_ watermark: Watermark, height: Double) -> CGImage? {
        if let name = watermark.imageName, !name.isEmpty,
           let url = storedImageURL(name),
           let picture = NSImage(contentsOf: url),
           let image = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return image
        }

        let text = watermark.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: height, weight: .semibold),
            // Mid grey, not white: the mark has to hold on a dark screenshot
            // and on a white page, and white disappears on the second.
            .foregroundColor: NSColor(white: 0.5, alpha: 1),
        ]
        let line = NSAttributedString(string: text, attributes: attributes)
        let size = line.size()
        let picture = NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)))
        picture.lockFocus()
        line.draw(at: .zero)
        picture.unlockFocus()
        return picture.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
