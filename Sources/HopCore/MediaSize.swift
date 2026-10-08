import Foundation

public enum MediaResolution: String, CaseIterable, Identifiable, Sendable {
    case double, quadruple, fullHD, qhd, fourK, eightK
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .double: return "×2"
        case .quadruple: return "×4"
        case .fullHD: return "Full HD"
        case .qhd: return "QHD"
        case .fourK: return "4K"
        case .eightK: return "8K"
        }
    }
}

public struct MediaSize: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
    public var text: String { "\(width) × \(height)" }
    public var rgbaBytes: Int? {
        guard width > 0, height > 0 else { return nil }
        let pixels = width.multipliedReportingOverflow(by: height)
        guard !pixels.overflow else { return nil }
        let bytes = pixels.partialValue.multipliedReportingOverflow(by: 4)
        return bytes.overflow ? nil : bytes.partialValue
    }
    public func inferenceTiles(to target: MediaSize) -> Int {
        guard width > 0, height > 0, width <= 7680, height <= 7680,
              target.width > width, target.height > height, target.width <= 7680, target.height <= 7680 else { return 0 }
        var current = self
        var total = 0
        while current.width < target.width || current.height < target.height {
            total += MediaTiles.tiles(for: current).count
            current = MediaSize(width: min(target.width, current.width * 4), height: min(target.height, current.height * 4))
        }
        return total
    }
    public var choices: [MediaResolution] { MediaResolution.allCases.filter { output(for: $0) != nil } }
    public func output(for choice: MediaResolution) -> MediaSize? {
        guard width > 0, height > 0, width <= 7680, height <= 7680 else { return nil }
        let landscape = width >= height
        let capW = landscape ? 7680 : 4320
        let capH = landscape ? 4320 : 7680
        let result: MediaSize
        switch choice {
        case .double, .quadruple:
            let factor = choice == .double ? 2 : 4
            result = MediaSize(width: width * factor, height: height * factor)
        default:
            let bounds: (Int, Int)
            switch choice {
            case .fullHD: bounds = (1920, 1080)
            case .qhd: bounds = (2560, 1440)
            case .fourK: bounds = (3840, 2160)
            default: bounds = (7680, 4320)
            }
            let w = landscape ? bounds.0 : bounds.1
            let h = landscape ? bounds.1 : bounds.0
            let ratio = min(Double(w) / Double(width), Double(h) / Double(height))
            guard ratio > 1 else { return nil }
            result = MediaSize(width: Int((Double(width) * ratio).rounded(.down)),
                               height: Int((Double(height) * ratio).rounded(.down)))
        }
        guard result.width > width, result.height > height,
              result.width <= capW, result.height <= capH else { return nil }
        return result
    }
}

public struct MediaTile: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
}

public enum MediaTiles {
    public static let input = 256
    public static let padding = 32
    public static let core = input - padding * 2
    public static func tiles(for size: MediaSize) -> [MediaTile] {
        guard size.width > 0, size.height > 0, size.width <= 7680, size.height <= 7680 else { return [] }
        return stride(from: 0, to: size.height, by: core).flatMap { y in
            stride(from: 0, to: size.width, by: core).map { x in
                MediaTile(x: x, y: y, width: min(core, size.width - x), height: min(core, size.height - y))
            }
        }
    }
}
