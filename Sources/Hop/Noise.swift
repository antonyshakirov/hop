import AppKit
import SwiftUI

/// Grain tile generated once: a barely visible film-like noise
/// on panel backgrounds. Static — moving grain is irritating.
enum NoiseTile {
    static let image: NSImage = {
        let side = 128
        var bytes = [UInt8](repeating: 0, count: side * side)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(
                  width: side, height: side,
                  bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider, decode: nil,
                  shouldInterpolate: false, intent: .defaultIntent
              )
        else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }()
}

struct NoiseOverlay: View {
    var body: some View {
        Rectangle()
            // scale 0.5 — grain at physical Retina pixels, finer and quieter
            .fill(ImagePaint(image: Image(nsImage: NoiseTile.image), scale: 0.5))
            .opacity(Theme.isDark ? 0.03 : 0.015)
            .blendMode(Theme.isDark ? .screen : .multiply)
            .allowsHitTesting(false)
    }
}
