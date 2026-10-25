import Foundation

/// Listening presentation/destination only. Never sent to a microphone worker.
public struct SoundAppPreference: Codable, Equatable, Sendable {
    public var name: String
    public var pinned = false
    public var order: Int?
    public var outputUID: String?
    public var outputName: String?
    public init(name: String) { self.name = name }
    private enum CodingKeys: String, CodingKey { case name, pinned, order, outputUID, outputName }
    public init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        name = try data.decodeIfPresent(String.self, forKey: .name) ?? ""
        pinned = try data.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        order = try data.decodeIfPresent(Int.self, forKey: .order)
        outputUID = try data.decodeIfPresent(String.self, forKey: .outputUID)
        outputName = try data.decodeIfPresent(String.self, forKey: .outputName)
    }
}

public enum SoundAppOutput {
    public static func allows(_ uid: String) -> Bool { !uid.hasPrefix("com.antonshakirov.hop.audio.") }
    public static func resolve(selectedUID: String?, systemUID: String?, available: Set<String>) -> String? {
        guard let uid = selectedUID ?? systemUID, available.contains(uid), allows(uid) else { return nil }
        return uid
    }
}

public enum SoundAppRouteState: Equatable, Sendable {
    case stopped, preparing, playing(String), waiting, failed
}

public enum SoundApplicationList {
    public static func ordered(_ ids: [String], names: [String: String],
                               preferences: [String: SoundAppPreference]) -> [String] {
        Array(Set(ids)).sorted { left, right in
            let a = preferences[left], b = preferences[right]
            if (a?.pinned ?? false) != (b?.pinned ?? false) { return a?.pinned == true }
            let x = a?.order ?? Int.max, y = b?.order ?? Int.max
            if x != y { return x < y }
            let comparison = (names[left] ?? left).localizedStandardCompare(names[right] ?? right)
            return comparison == .orderedSame ? left < right : comparison == .orderedAscending
        }
    }

    public static func moving(_ id: String, by offset: Int, ids: [String], names: [String: String],
                              preferences: [String: SoundAppPreference]) -> [String: SoundAppPreference] {
        var ordered = ordered(ids, names: names, preferences: preferences)
        guard let from = ordered.firstIndex(of: id), abs(offset) == 1 else { return preferences }
        let to = from + offset
        guard ordered.indices.contains(to),
              (preferences[id]?.pinned ?? false) == (preferences[ordered[to]]?.pinned ?? false) else { return preferences }
        ordered.swapAt(from, to)
        var result = preferences
        for (rank, key) in ordered.enumerated() {
            var value = result[key] ?? SoundAppPreference(name: names[key] ?? key)
            value.order = rank; result[key] = value
        }
        return result
    }
}
