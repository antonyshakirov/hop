import AppKit
import HopCore
import UniformTypeIdentifiers

/// The finished picture: marks, crop, watermark and dressing, then a file or
/// the clipboard.
enum MarkupExport {
    static func render(
        base: CGImage,
        shapes: [MarkupShape],
        scale: Double,
        crop: CaptureRect?,
        dressing: FrameDressing,
        watermark: Watermark
    ) -> CGImage? {
        var picture = MarkupRender.compose(base: base, shapes: shapes, scale: scale) ?? base

        if let crop, crop.isUsable {
            let box = CGRect(x: crop.x * scale, y: crop.y * scale,
                             width: Double(crop.pixelWidth), height: Double(crop.pixelHeight))
            if let cut = picture.cropping(to: box) { picture = cut }
        }
        // The mark goes on the PICTURE, before the dressing widens the canvas.
        // Stamped afterwards it lands on the background poured around the shot,
        // which is not what a watermark is for.
        if let stamped = WatermarkRenderer.stamp(watermark, on: picture) { picture = stamped }
        if let dressed = FrameDressingRenderer.dress(picture, with: dressing) { picture = dressed }
        return picture
    }

    static func write(_ image: CGImage, to url: URL, format: String) throws {
        let type: UTType = format.lowercased() == "jpg" || format.lowercased() == "jpeg" ? .jpeg : .png
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, 1, nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func copy(_ image: CGImage) {
        let picture = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([picture])
    }

    /// Where shots go by default, and where the settings point once changed.
    static func folder() -> URL {
        if let stored = UserDefaults.standard.string(forKey: "shotFolder"), !stored.isEmpty {
            return URL(fileURLWithPath: stored)
        }
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let folder = pictures.appendingPathComponent("Hop", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func save(_ image: CGImage, format: String, name: String? = nil) -> URL? {
        let folder = folder()
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let wanted = name ?? ScreenshotNaming.fileName(at: Date(), calendar: .current, format: format)
        let unique = ScreenshotNaming.unique(wanted, taken: taken)
        let url = folder.appendingPathComponent(unique)
        do {
            try write(image, to: url, format: format)
            return url
        } catch {
            return nil
        }
    }
}
