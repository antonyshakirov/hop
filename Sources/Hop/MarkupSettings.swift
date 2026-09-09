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
    static let arrowStyleKey = "markupArrowStyle"
    static let inksKey = "markupInks"
    static let recentColoursKey = "markupRecentColours"
    static let sharedColourKey = "markupSharedColour"
    static let commonColourKey = "markupCommonColour"

    static func frameDressing() -> FrameDressing {
        decode(dressingKey) ?? .standard
    }

    static func watermark() -> Watermark {
        decode(watermarkKey) ?? .standard
    }

    static func arrowStyle() -> ArrowStyle {
        guard let raw = UserDefaults.standard.string(forKey: arrowStyleKey),
              let style = ArrowStyle(rawValue: raw) else { return ArrowStyle.allCases[0] }
        return style
    }

    /// Colour and width per tool. Each is its own setting and each outlives the
    /// session: the fat yellow marker is not the thin red pencil.
    static func inks() -> [MarkupTool: MarkupInk] {
        let stored: [String: MarkupInk] = decode(inksKey) ?? [:]
        return stored.reduce(into: [:]) { out, pair in
            guard let tool = MarkupTool(rawValue: pair.key) else { return }
            out[tool] = pair.value
        }
    }

    /// One colour for every tool, or a colour per tool. Off unless the user
    /// says otherwise — a red pencil beside a yellow marker is what a hand
    /// reaches for.
    static func sharedColour() -> Bool {
        UserDefaults.standard.object(forKey: sharedColourKey) as? Bool ?? false
    }

    static func commonColour() -> String? {
        UserDefaults.standard.string(forKey: commonColourKey)
    }

    static func store(commonColour hex: String?) {
        if let hex {
            UserDefaults.standard.set(hex, forKey: commonColourKey)
        } else {
            UserDefaults.standard.removeObject(forKey: commonColourKey)
        }
    }

    static func store(inks: [MarkupTool: MarkupInk]) {
        let plain = inks.reduce(into: [String: MarkupInk]()) { out, pair in
            out[pair.key.rawValue] = pair.value
        }
        encode(plain, into: inksKey)
    }

    /// Colours mixed by hand, newest first. A colour chosen for one tool is a
    /// colour the next tool should be able to reach without mixing it again.
    static func recentColours() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentColoursKey) ?? []
    }

    static func remember(colour hex: String) {
        var kept = recentColours().filter { $0.caseInsensitiveCompare(hex) != .orderedSame }
        kept.insert(hex, at: 0)
        UserDefaults.standard.set(Array(kept.prefix(7)), forKey: recentColoursKey)
    }

    static func store(arrowStyle: ArrowStyle) {
        UserDefaults.standard.set(arrowStyle.rawValue, forKey: arrowStyleKey)
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
