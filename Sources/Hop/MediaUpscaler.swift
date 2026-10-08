import AppKit
import CoreML
import HopCore

final class MediaUpscaler {
    private let model: MLModel
    init(modelURL: URL = MediaModelStore.compiled) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        do { model = try MLModel(contentsOf: modelURL, configuration: configuration) }
        catch { throw MediaFailure.model }
        guard model.modelDescription.inputDescriptionsByName["input"]?.multiArrayConstraint?.shape == [1, 3, 256, 256],
              model.modelDescription.outputDescriptionsByName["output"]?.multiArrayConstraint?.shape == [1, 3, 1024, 1024]
        else { throw MediaFailure.model }
    }

    func enhance(_ image: CGImage, to target: MediaSize, progress: (Double) -> Void) throws -> CGImage {
        guard target.width > image.width, target.height > image.height,
              target.width <= 7680, target.height <= 7680, target.rgbaBytes != nil else { throw MediaFailure.tooLarge }
        var current = image
        let totalPasses = max(1, Int(ceil(log(Double(target.width) / Double(image.width)) / log(4))))
        for pass in 0..<totalPasses {
            try Task.checkCancellation()
            let last = pass == totalPasses - 1
            let size = last ? target : MediaSize(width: min(target.width, current.width * 4), height: min(target.height, current.height * 4))
            current = try enhancePass(current, to: size) { value in
                progress((Double(pass) + value) / Double(totalPasses))
            }
        }
        return current
    }

    private func enhancePass(_ image: CGImage, to target: MediaSize, progress: (Double) -> Void) throws -> CGImage {
        let source = MediaSize(width: image.width, height: image.height)
        let pixels = try MediaImageEngine.pixels(image)
        guard let canvas = MediaImageEngine.bitmap(target) else { throw MediaFailure.tooLarge }
        canvas.interpolationQuality = .high
        let tiles = MediaTiles.tiles(for: source)
        guard !tiles.isEmpty else { throw MediaFailure.tooLarge }
        for (index, tile) in tiles.enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                let input = try MLMultiArray(shape: [1, 3, 256, 256], dataType: .float16)
                let ptr = input.dataPointer.assumingMemoryBound(to: Float16.self)
                for y in 0..<256 {
                    let sy = min(source.height - 1, max(0, tile.y + y - MediaTiles.padding))
                    for x in 0..<256 {
                        let sx = min(source.width - 1, max(0, tile.x + x - MediaTiles.padding))
                        let at = (sy * source.width + sx) * 4
                        let alpha = Float(pixels[at + 3])
                        for c in 0..<3 {
                            ptr[c * 256 * 256 + y * 256 + x] = Float16(alpha > 0 ? Float(pixels[at + c]) / alpha : 0)
                        }
                    }
                }
                let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input": input]))
                guard let out = result.featureValue(for: "output")?.multiArrayValue,
                      out.dataType == .float16, out.shape == [1, 3, 1024, 1024] else { throw MediaFailure.model }
                let output = out.dataPointer.assumingMemoryBound(to: Float16.self)
                let strides = out.strides.map(\.intValue)
                let width = tile.width * 4, height = tile.height * 4
                var rgba = [UInt8](repeating: 255, count: width * height * 4)
                for y in 0..<height {
                    for x in 0..<width {
                        for c in 0..<3 {
                            let at = c * strides[1] + (y + 128) * strides[2] + (x + 128) * strides[3]
                            let value = Float(output[at])
                            rgba[(y * width + x) * 4 + c] = value.isFinite ? UInt8(max(0, min(255, value * 255))) : 0
                        }
                    }
                }
                guard let provider = CGDataProvider(data: Data(rgba) as CFData),
                      let patch = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                        bytesPerRow: width * 4, space: MediaImageEngine.colorSpace,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                else { throw MediaFailure.output }
                let x0 = tile.x * target.width / source.width
                let x1 = (tile.x + tile.width) * target.width / source.width
                let y0 = tile.y * target.height / source.height
                let y1 = (tile.y + tile.height) * target.height / source.height
                canvas.draw(patch, in: CGRect(x: x0, y: target.height - y1, width: x1 - x0, height: y1 - y0))
            }
            progress(Double(index + 1) / Double(tiles.count))
        }
        guard let enhanced = canvas.makeImage() else { throw MediaFailure.output }
        let alpha = CIImage(cgImage: try MediaImageEngine.resize(image, to: target))
        let opaque = CIImage(cgImage: enhanced)
        let masked = opaque.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: opaque.extent), kCIInputMaskImageKey: alpha
        ])
        guard let final = MediaImageEngine.context.createCGImage(masked, from: opaque.extent,
                                                                 format: .RGBA8, colorSpace: MediaImageEngine.colorSpace)
        else { throw MediaFailure.output }
        return final
    }
}
