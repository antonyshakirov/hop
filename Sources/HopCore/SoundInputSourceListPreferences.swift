import Foundation

public enum SoundInputSourceID: Codable, Hashable, Sendable {
    case device(String), application(String)

    public var value: String {
        switch self { case .device(let value), .application(let value): value }
    }
    public var kind: String {
        switch self { case .device: "device"; case .application: "app" }
    }
    public var allowed: Bool {
        guard !value.isEmpty, value.count <= 512,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return false }
        switch self {
        case .device: return SoundInputMixPreferences.allowsMicrophone(value)
        case .application: return SoundCallMixPolicy.allows(value)
        }
    }
}

/// SPEC: product-spec/implementation/input-source-list.md — presentation never changes audio settings.
public struct SoundInputSourceListPreferences: Codable, Equatable, Sendable {
    public var schema = 1
    public private(set) var pinned: Set<SoundInputSourceID> = []
    public private(set) var hidden: Set<SoundInputSourceID> = []
    public private(set) var names: [SoundInputSourceID: String] = [:]
    public init() {}

    public static func load(_ data: Data?) -> Self {
        guard let data, data.count <= 1_048_576,
              var value = try? JSONDecoder().decode(Self.self, from: data), value.schema == 1 else { return .init() }
        value.pinned = Set(value.pinned.filter(\.allowed))
        value.hidden = Set(value.hidden.filter(\.allowed)).subtracting(value.pinned)
        value.names = value.names.filter { $0.key.allowed && !$0.value.isEmpty && $0.value.count <= 512 }
        return value
    }
    public mutating func remember(_ name: String, source: SoundInputSourceID) {
        guard source.allowed, !name.isEmpty, name.count <= 512 else { return }
        names[source] = name
    }
    public mutating func setPinned(_ value: Bool, source: SoundInputSourceID) {
        guard source.allowed else { return }
        if value { pinned.insert(source); hidden.remove(source) }
        else { pinned.remove(source) }
    }
    @discardableResult public mutating func setHidden(_ value: Bool, source: SoundInputSourceID, selected: Bool) -> Bool {
        guard source.allowed, !value || !selected else { return false }
        if value { hidden.insert(source); pinned.remove(source) }
        else { hidden.remove(source) }
        return true
    }
    public func groups(_ sources: [SoundInputSourceID], selected: Set<SoundInputSourceID>)
        -> (primary: [SoundInputSourceID], other: [SoundInputSourceID], hidden: [SoundInputSourceID]) {
        var seen: Set<SoundInputSourceID> = []
        let unique = sources.filter { $0.allowed && seen.insert($0).inserted }
        let primary = unique.filter { pinned.contains($0) } + unique.filter { selected.contains($0) && !pinned.contains($0) }
        let other = unique.filter { !pinned.contains($0) && !selected.contains($0) && !hidden.contains($0) }
        return (primary, other, unique.filter { hidden.contains($0) && !selected.contains($0) })
    }
}
