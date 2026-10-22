import Foundation

public enum SoundDirection: String, CaseIterable, Sendable {
    case output, input
}

public struct SoundDevice: Identifiable, Equatable, Sendable {
    public var id: String { uid }
    public var uid: String
    public var name: String
    public var volume: Double?
    public var muted: Bool?
    public var canChangeVolume: Bool
    public var canMute: Bool

    public init(uid: String, name: String, volume: Double? = nil, muted: Bool? = nil,
                canChangeVolume: Bool = false, canMute: Bool = false) {
        self.uid = uid
        self.name = name
        self.volume = volume
        self.muted = muted
        self.canChangeVolume = canChangeVolume
        self.canMute = canMute
    }
}

/// SPEC: docs/spec.md — "Sound": channel balance survives a volume change.
public enum SoundGain {
    public static func adjusted(_ values: [Double], target: Double) -> [Double]? {
        guard !values.isEmpty, target.isFinite,
              values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        let target = min(1, max(0, target))
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return values.map { _ in target } }
        let scale = min(target / mean, 1 / (values.max() ?? 1))
        return values.map { min(1, max(0, $0 * scale)) }
    }
}

public enum SoundLevel {
    public static func normalized(rms: Double) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }
        return min(1, max(0, (20 * log10(rms) + 60) / 60))
    }
}

public enum SoundPercentage {
    public static func value(_ input: String, maximum: Double = 100) -> Double? {
        guard maximum.isFinite, maximum > 0, input.count <= 32 else { return nil }
        let text = input.filter { !$0.isWhitespace && $0 != "%" && $0 != "٪" }
            .map { character in character.wholeNumberValue.map(String.init) ?? String(character) }.joined()
            .replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "٫", with: ".")
        guard !text.isEmpty, text.allSatisfy({ $0.isNumber || ".+-".contains($0) }),
              let percent = Double(text), percent.isFinite else { return nil }
        return min(maximum, max(0, percent)) / 100
    }
}

/// SPEC: docs/spec.md — "Sound": roll back channels written before a failure.
public enum SoundControlTransaction {
    public static func apply<T>(_ values: [T], originals: [T],
                                write: (Int, T) throws -> Void) throws {
        precondition(values.count == originals.count)
        var completed = 0
        do {
            for i in values.indices { try write(i, values[i]); completed += 1 }
        } catch {
            for i in 0..<completed { try? write(i, originals[i]) }
            throw error
        }
    }
}
