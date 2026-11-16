import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import Hop

final class ClipboardHoverImageLoaderTests: XCTestCase {
    func testPNGBecomesABoundedThumbnailAndCacheReusesIt() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        try writeImage(directory.appendingPathComponent("sample.png"))
        let loader = ClipboardHoverImageLoader()
        let loaded = await loader.load(file: "sample.png", directory: directory)
        let image = try XCTUnwrap(loaded)
        XCTAssertLessThanOrEqual(image.image.width, 640)
        XCTAssertLessThanOrEqual(image.image.height, 640)
        XCTAssertEqual(Double(image.image.width) / Double(image.image.height), 1008.0 / 370, accuracy: 0.02)
        let again = await loader.load(file: "sample.png", directory: directory)
        XCTAssertTrue(image === again)
    }

    func testTraversalSymlinksAndWrongFormatAreRejected() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        try writeImage(directory.appendingPathComponent("sample.png"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link.png"),
                                                 withDestinationURL: directory.appendingPathComponent("sample.png"))
        try writeImage(directory.appendingPathComponent("jpeg.png"), type: "public.jpeg")
        let loader = ClipboardHoverImageLoader()
        for file in ["../sample.png", "/sample.png", "bad\0.png", "link.png", "jpeg.png", "missing.png"] {
            let image = await loader.load(file: file, directory: directory)
            XCTAssertNil(image, file)
        }
    }

    func testOversizedFileAndUnsafeDimensionsAreRejectedBeforeDecode() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("large.png")
        try writeImage(url)
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: UInt64(ClipboardHoverImageLoader.maximumInputBytes + 1)); try file.close()
        let loader = ClipboardHoverImageLoader()
        let image = await loader.load(file: "large.png", directory: directory)
        XCTAssertNil(image)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertNotNil(CGImageSourceCreateThumbnailAtIndex(source, 0,
            [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 640] as CFDictionary))
        try writeImage(directory.appendingPathComponent("wide.png"), width: 32769, height: 1)
        let wide = await loader.load(file: "wide.png", directory: directory)
        XCTAssertNil(wide)
        for size in [(Double.nan, 1.0), (1.0, Double.infinity), (0.0, 1.0), (32769.0, 1.0), (8001.0, 8000.0)] {
            XCTAssertFalse(ClipboardHoverImageLoader.validDimensions(width: size.0, height: size.1))
        }
        XCTAssertTrue(ClipboardHoverImageLoader.validDimensions(width: 8000, height: 8000))
    }

    func testCacheHasAHardByteAndEntryBudget() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try writeImage(original, width: 1024, height: 1024)
        let loader = ClipboardHoverImageLoader()
        for index in 0..<16 {
            let name = "\(index).png"
            try FileManager.default.copyItem(at: original, to: directory.appendingPathComponent(name))
            let image = await loader.load(file: name, directory: directory)
            XCTAssertNotNil(image)
        }
        let usage = await loader.usage
        XCTAssertLessThanOrEqual(usage.count, 12)
        XCTAssertLessThanOrEqual(usage.bytes, ClipboardHoverImageLoader.maximumCacheBytes)
    }

    func testSmallImagesStillRespectTheEntryLimit() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try writeImage(original, width: 20, height: 20)
        let loader = ClipboardHoverImageLoader()
        for index in 0..<16 {
            let name = "\(index).png"
            try FileManager.default.copyItem(at: original, to: directory.appendingPathComponent(name))
            _ = await loader.load(file: name, directory: directory)
        }
        let usage = await loader.usage
        XCTAssertEqual(usage.count, 12)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hover-images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeImage(_ url: URL, type: String = "public.png", width: Int = 1008, height: Int = 370) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
