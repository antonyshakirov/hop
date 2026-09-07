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
            let step = Watermark.tileStep(of: size)
            var y = 0.0
            while y < frame.y {
                var x = 0.0
                while x < frame.x {
                    context.draw(mark, in: CGRect(x: x, y: y, width: size.x, height: size.y))
                    x += step.x
                }
                y += step.y
            }
        } else {
            let spot = Watermark.origin(of: size, in: frame, spot: watermark.spot, inset: inset)
            // The spot is named from the top; Core Graphics counts from below.
            context.draw(mark, in: CGRect(x: spot.x, y: frame.y - spot.y - size.y,
                                          width: size.x, height: size.y))
        }
        return context.makeImage()
    }

    /// Where an image watermark is kept: a copy of its own, so a file moved or
    /// deleted later cannot silently empty the mark.
    static func store(imageAt url: URL) -> String? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }

        let folder = support.appendingPathComponent("Hop", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "watermark.\(url.pathExtension.isEmpty ? "png" : url.pathExtension)"
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
            .foregroundColor: NSColor.white,
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
