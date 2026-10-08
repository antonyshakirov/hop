import AppKit
import CoreImage
import HopCore
import ImageIO
import UniformTypeIdentifiers
import Vision

enum MediaOperation: String, CaseIterable { case background, upscale }
enum MediaFailure: Error, Equatable { case input, tooLarge, noSubject, model, download, output, codec }
enum MediaBackground: @unchecked Sendable {
    case transparent
    case color(CGColor)
    case image(CGImage)
}

enum MediaImageEngine {
    static let context = CIContext(options: [.cacheIntermediates: false])
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func read(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { throw MediaFailure.input }
        guard w <= 16384, h <= 16384, Int64(w) * Int64(h) <= 100_000_000 else { throw MediaFailure.tooLarge }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw MediaFailure.input }
        return image
    }

    static func resize(_ image: CGImage, to size: MediaSize) throws -> CGImage {
        guard let ctx = bitmap(size) else { throw MediaFailure.output }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let result = ctx.makeImage() else { throw MediaFailure.output }
        return result
    }

    static func bitmap(_ size: MediaSize) -> CGContext? {
        guard let bytes = size.rgbaBytes, bytes <= 400_000_000 else { return nil }
        return CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                         bytesPerRow: size.width * 4, space: colorSpace,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func pixels(_ image: CGImage) throws -> [UInt8] {
        let size = MediaSize(width: image.width, height: image.height)
        guard let ctx = bitmap(size), let data = ctx.data, let count = size.rgbaBytes else { throw MediaFailure.tooLarge }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: count))
    }

    static func foreground(_ image: CGImage, subject: Int = 0) throws -> (CGImage, [Int]) {
        try Task.checkCancellation()
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else { throw MediaFailure.noSubject }
        let selection = subject == 0 ? result.allInstances : IndexSet(integer: subject)
        guard selection.isSubset(of: result.allInstances) else { throw MediaFailure.noSubject }
        let mask = try result.generateScaledMaskForImage(forInstances: selection, from: handler)
        let masked = try applyMask(CIImage(cvPixelBuffer: mask), to: CIImage(cgImage: image))
        return (masked, Array(result.allInstances))
    }

    static func applyMask(_ mask: CIImage, to input: CIImage) throws -> CGImage {
        let fitted = mask.transformed(by: CGAffineTransform(scaleX: input.extent.width / mask.extent.width,
                                                           y: input.extent.height / mask.extent.height))
        let clear = CIImage(color: .clear).cropped(to: input.extent)
        let composed = input.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: clear,
                                                                          kCIInputMaskImageKey: fitted])
        guard let image = context.createCGImage(composed, from: input.extent, format: .RGBA8, colorSpace: colorSpace)
        else { throw MediaFailure.output }
        return image
    }

    static func replaceBackground(_ image: CGImage, with background: MediaBackground) throws -> CGImage {
        let front = CIImage(cgImage: image)
        let back: CIImage
        switch background {
        case .transparent: return image
        case .color(let color): back = CIImage(color: CIColor(cgColor: color)).cropped(to: front.extent)
        case .image(let picture):
            let source = CIImage(cgImage: picture)
            let scale = max(front.extent.width / source.extent.width, front.extent.height / source.extent.height)
            let fitted = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            back = fitted.transformed(by: CGAffineTransform(translationX: (front.extent.width - fitted.extent.width) / 2,
                                                            y: (front.extent.height - fitted.extent.height) / 2))
        }
        let combined = front.composited(over: back)
        guard let result = context.createCGImage(combined, from: front.extent, format: .RGBA8, colorSpace: colorSpace)
        else { throw MediaFailure.output }
        return result
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try Task.checkCancellation()
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw MediaFailure.output }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw MediaFailure.output }
    }
}
