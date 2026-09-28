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

    /// Tags of the reader Vision compiles on the spot, per line width, instead of
    /// shipping it precompiled.
    public static let compiledOnTheSpot: Set<String> = ["ja-JP", "zh-Hans", "zh-Hant"]

    /// The first pass before the warm-up has run: the reader's own language and
    /// English, named, so nothing is compiled while the user waits. A reader
    /// whose own script needs the slow model keeps it.
    public static func quickLanguages(interface: TextScript, supported: [String]) -> [String] {
        var tags: [String] = []
        for tag in [interface.recognitionTag, TextScript.latin.recognitionTag]
        where supported.contains(tag) && !tags.contains(tag) {
            tags.append(tag)
        }
        return tags
    }

    /// The second pass before the warm-up has run keeps away from the slow model
    /// unless the reader's own script needs it.
    public static func quickHelpers(_ tags: [String], interface: TextScript) -> [String] {
        tags.filter { !compiledOnTheSpot.contains($0) || $0 == interface.recognitionTag }
    }
}
