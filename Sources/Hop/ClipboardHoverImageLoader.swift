import CoreGraphics
import Darwin
import Foundation
import ImageIO

// SPEC: docs/spec.md — Clipboard, bounded image hover previews.
final class ClipboardHoverBitmap: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

actor ClipboardHoverImageLoader {
    static let shared = ClipboardHoverImageLoader()
    static let maximumInputBytes = 25 * 1024 * 1024
    static let maximumPixelSize = 640
    static let maximumCacheBytes = 8 * 1024 * 1024
    private var cache: [String: (image: ClipboardHoverBitmap, cost: Int)] = [:]
    private var recent: [String] = []
    private var cacheBytes = 0
    var usage: (count: Int, bytes: Int) { (cache.count, cacheBytes) }

    func load(file: String, directory: URL) -> ClipboardHoverBitmap? {
        guard !Task.isCancelled, !file.isEmpty, file.utf8.count <= 255,
              !file.utf8.contains(0), !file.contains("/"), !file.contains("\\"),
              file.lowercased().hasSuffix(".png"), directory.isFileURL else { return nil }
        let url = directory.appendingPathComponent(file), key = url.path
        if let cached = cache[key] {
            recent.removeAll { $0 == key }; recent.append(key)
            return cached.image
        }
        guard let data = Self.readFile(url),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source), type as String == "public.png",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue,
              Self.validDimensions(width: width, height: height), !Task.isCancelled,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixelSize
              ] as CFDictionary), !Task.isCancelled else { return nil }
        let result = ClipboardHoverBitmap(image)
        store(result, key: key)
        return result
    }

    private func store(_ image: ClipboardHoverBitmap, key: String) {
        let cost = image.image.bytesPerRow * image.image.height
        guard cost <= Self.maximumCacheBytes else { return }
        while !recent.isEmpty && (cache.count >= 12 || cacheBytes + cost > Self.maximumCacheBytes) {
            let oldest = recent.removeFirst()
            if let removed = cache.removeValue(forKey: oldest) { cacheBytes -= removed.cost }
        }
        cache[key] = (image, cost); cacheBytes += cost; recent.append(key)
    }

    private static func readFile(_ url: URL) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size > 0, metadata.st_size <= Int64(maximumInputBytes) else { return nil }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var data = Data(); data.reserveCapacity(Int(metadata.st_size))
        do {
            while data.count <= maximumInputBytes, !Task.isCancelled {
                guard let chunk = try file.read(upToCount: min(65536, maximumInputBytes + 1 - data.count)), !chunk.isEmpty else { break }
                data.append(chunk)
            }
        } catch { return nil }
        return !Task.isCancelled && !data.isEmpty && data.count <= maximumInputBytes ? data : nil
    }

    static func validDimensions(width: Double, height: Double) -> Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
            && width <= 32768 && height <= 32768 && width * height <= 64_000_000
    }
}
