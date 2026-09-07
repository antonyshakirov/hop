import Foundation
import HopCore

/// What the two markup modules remember between captures: where shots go, how
/// the frame is dressed and what the watermark says.
enum MarkupSettings {
    static let folderKey = "shotFolder"
    static let formatKey = "shotFormat"
    static let delayKey = "shotDelay"
    static let pointerKey = "shotPointer"
    static let dressingKey = "shotDressing"
    static let watermarkKey = "shotWatermark"
    static let shotEdgeKey = "shotToolbarEdge"
    static let annotateEdgeKey = "annotateToolbarEdge"

    static func frameDressing() -> FrameDressing {
        decode(dressingKey) ?? .standard
    }

    static func watermark() -> Watermark {
        decode(watermarkKey) ?? .standard
    }

    static func store(dressing: FrameDressing, watermark: Watermark) {
        encode(dressing, into: dressingKey)
        encode(watermark, into: watermarkKey)
    }

    private static func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, into key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
