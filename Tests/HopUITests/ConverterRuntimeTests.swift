import AppKit
import PDFKit
import XCTest
@testable import Hop

@MainActor
final class ConverterRuntimeTests: XCTestCase {
    func testAppSoundsAreSilentUnderTest() {
        XCTAssertTrue(Sounds.underTest)
        XCTAssertFalse(Sounds.enabled)
    }

    func testImageAndPDFBatchConversionOnCurrentMac() throws {
        let defaults = UserDefaults.standard
        let keys = [FileConverter.destKey, FileConverter.destPathKey,
                    FileConverter.formatKey, FileConverter.scaleKey,
                    FileConverter.qualityKey, FileConverter.autoClearKey,
                    FileConverter.pdfModeKey]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hop-converter-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        defaults.set("custom", forKey: FileConverter.destKey)
        defaults.set(root.path, forKey: FileConverter.destPathKey)
        defaults.set("jpeg", forKey: FileConverter.formatKey)
        defaults.set(0.5, forKey: FileConverter.scaleKey)
        defaults.set(55, forKey: FileConverter.qualityKey)
        defaults.set(false, forKey: FileConverter.autoClearKey)
        defaults.set("compress", forKey: FileConverter.pdfModeKey)

        let image = root.appendingPathComponent("source.png")
        let asset = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("assets/icon/hop-icon-dark-512.png")
        try FileManager.default.copyItem(at: asset, to: image)
        let converter = FileConverter()
        converter.addToBatch([image])
        awaitReady { !converter.batch.images.isEmpty }
        XCTAssertEqual(converter.batch.images.count, 1)
        converter.convert(.image)
        awaitReady { !converter.busy && converter.lastOutput != nil }
        let convertedImage = try XCTUnwrap(converter.lastOutput)
        XCTAssertEqual(convertedImage.pathExtension, "jpg")
        XCTAssertNotNil(NSImage(contentsOf: convertedImage))

        let pdf = root.appendingPathComponent("source.pdf")
        XCTAssertTrue(DocumentConversion.writePDF(NSAttributedString(string: "Hop macOS 27 smoke"), to: pdf))
        converter.addToBatch([pdf])
        awaitReady { !converter.batch.pdfs.isEmpty }
        XCTAssertEqual(converter.batch.pdfs.count, 1)
        converter.convert(.pdf)
        awaitReady { !converter.busy && converter.lastOutput?.pathExtension == "pdf" }
        let convertedPDF = try XCTUnwrap(converter.lastOutput)
        XCTAssertGreaterThan(PDFDocument(url: convertedPDF)?.pageCount ?? 0, 0)
    }

    private func awaitReady(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}
