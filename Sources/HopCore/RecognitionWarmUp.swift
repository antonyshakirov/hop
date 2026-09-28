import Foundation

/// SPEC: docs/spec.md — "The first reading after an update is not the slow one".
public enum RecognitionWarmUp {
    public static func key(size: Int, modified: Date) -> String {
        "\(size)-\(Int(modified.timeIntervalSince1970))"
    }

    public static func isDue(warmedFor: String?, current: String?, moduleOn: Bool) -> Bool {
        guard moduleOn, let current else { return false }
        return warmedFor != current
    }

    public static let shapes: [(width: Int, height: Int)] = [
        (2000, 1200), (1400, 520), (600, 600), (840, 90),
    ]

    public static func helperTagSets(interface: TextScript, supported: [String]) -> [[String]] {
        let scripts: [TextScript] = interface == .latin ? [.latin] : [.latin, interface]
        var sets: [[String]] = []
        for dominant in scripts {
            let tags = ScriptMerge.helperLanguages(seen: Set(scripts), dominant: dominant,
                                                   interface: interface, supported: supported)
            if !tags.isEmpty, !sets.contains(tags) { sets.append(tags) }
        }
        return sets
    }
}
