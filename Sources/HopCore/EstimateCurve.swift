import Foundation

/// Size-estimate math for the converter: real measurements at a few
/// reference quality points, linear interpolation in between. Pure and
/// unit-tested; FileConverter does the trial conversions and owns the cache.
public struct EstimateCurve: Equatable {
    // cache identity: the curve is only valid for the same sample and settings
    public let samplePath: String
    public let format: String
    public let scale: Double
    public let totalBytes: Int64
    public let sampleBytes: Int64
    /// Measured output size of the sample at each reference quality (0...100).
    public let points: [Int: Int64]

    public init(
        samplePath: String, format: String, scale: Double,
        totalBytes: Int64, sampleBytes: Int64, points: [Int: Int64]
    ) {
        self.samplePath = samplePath
        self.format = format
        self.scale = scale
        self.totalBytes = totalBytes
        self.sampleBytes = sampleBytes
        self.points = points
    }

    /// Linear interpolation between reference measurements: the sample's
    /// output size at the given quality. Clamps outside the measured range.
    public func sampleOutputBytes(atQuality quality: Int) -> Double {
        let keys = points.keys.sorted()
        guard let first = keys.first, let last = keys.last else { return 0 }
        if quality <= first { return Double(points[first] ?? 0) }
        if quality >= last { return Double(points[last] ?? 0) }
        var lower = first
        var upper = last
        for k in keys {
            if k <= quality { lower = k }
            if k >= quality { upper = k; break }
        }
        let a = Double(points[lower] ?? 0)
        let b = Double(points[upper] ?? 0)
        let f = upper == lower ? 0 : Double(quality - lower) / Double(upper - lower)
        return a + (b - a) * f
    }

    /// Sample compression ratio at the given quality (output ÷ input).
    public func ratio(atQuality quality: Int) -> Double {
        guard sampleBytes > 0 else { return 0 }
        return sampleOutputBytes(atQuality: quality) / Double(sampleBytes)
    }

    /// The whole group projected through the sample's ratio;
    /// nil when the curve has no usable data.
    public func projectedTotal(atQuality quality: Int) -> Int64? {
        let sampleOut = sampleOutputBytes(atQuality: quality)
        guard sampleOut > 0, sampleBytes > 0 else { return nil }
        return Int64(Double(totalBytes) * sampleOut / Double(sampleBytes))
    }
}

public enum SizeFormatting {
    /// Decimal units, exactly like Finder — the number users compare
    /// against; binary MiB read ~5% smaller and made every result look
    /// heavier than promised.
    public static func sizeText(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1000) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1000)
    }
}
