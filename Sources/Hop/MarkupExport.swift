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
        finish(MarkupRender.compose(base: base, shapes: shapes, scale: scale),
               scale: scale, crop: crop, dressing: dressing, watermark: watermark)
    }

    /// SPEC: docs/spec.md — an export that cannot hide what it was told to hide gives back nothing.
    static func finish(
        _ composed: CGImage?,
        scale: Double,
        crop: CaptureRect?,
        dressing: FrameDressing,
        watermark: Watermark
    ) -> CGImage? {
        guard var picture = composed else { return nil }

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

    /// SPEC: docs/spec.md — copy says it copied, and only when it did.
    static func copy(_ image: CGImage, to pasteboard: NSPasteboard = .general) -> Bool {
        let picture = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        pasteboard.clearContents()
        return pasteboard.writeObjects([picture])
    }

    /// Where shots go by default, and where the settings point once changed.
    static func folder() -> URL {
        let manager = FileManager.default
        return ScreenshotNaming.folder(
            stored: UserDefaults.standard.string(forKey: MarkupSettings.folderKey),
            desktop: manager.urls(for: .desktopDirectory, in: .userDomainMask).first,
            home: manager.homeDirectoryForCurrentUser)
    }

    static func save(_ image: CGImage, format: String, name: String? = nil,
                     into folder: URL = MarkupExport.folder()) -> URL? {
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let wanted = name.flatMap { ScreenshotNaming.cleaned($0, format: format) }
            ?? ScreenshotNaming.fileName(at: Date(), calendar: .current, format: format)
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
