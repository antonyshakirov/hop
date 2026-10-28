import AppKit
import HopCore

struct SoundInputListSource: Identifiable {
    let id: SoundInputSourceID
    let name: String
    var available: Bool
    var isVirtual = false
    func displayName(_ lang: AppLanguage) -> String {
        guard name == id.value else { return name }
        switch id {
        case .device: return L10n.t(.soundMicrophone, lang)
        case .application(let bundleID):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                  let bundle = Bundle(url: url) else { return name }
            return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
        }
    }
}

@MainActor
struct SoundInputSourceList {
    let primary: [SoundInputListSource]
    let other: [SoundInputListSource]
    let hidden: [SoundInputListSource]

    init(call: SoundCallMixController, devices: [SoundDevice],
         applications: [(id: String, name: String, available: Bool)]) {
        func name(_ value: String, id: SoundInputSourceID) -> String {
            value == id.value ? call.sourceList.names[id] ?? value : value
        }
        var sources = devices.map { SoundInputListSource(id: .device($0.uid), name: name($0.name, id: .device($0.uid)), available: true, isVirtual: $0.isVirtual) }
        sources += applications.map { SoundInputListSource(id: .application($0.id), name: name($0.name, id: .application($0.id)), available: $0.available) }
        var seen = Set(sources.map(\.id))
        let retained = Set(call.sourceList.names.keys).union(call.sourceList.pinned).union(call.sourceList.hidden)
            .union(call.microphones.filter { $0.value.active }.keys.map(SoundInputSourceID.device))
            .union(call.applications.filter { $0.value.active }.keys.map(SoundInputSourceID.application))
        for id in retained.sorted(by: { $0.kind + $0.value < $1.kind + $1.value }) where seen.insert(id).inserted {
            sources.append(.init(id: id, name: call.sourceList.names[id] ?? id.value, available: false))
        }
        let groups = call.sourceList.groups(sources.map(\.id), selected: Set(sources.filter { call.sourceSelected($0.id) }.map(\.id)))
        let byID = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let physical = groups.other.filter { id in
            guard case .device = id, let source = byID[id] else { return false }
            return source.available && !source.isVirtual
        }
        let visible = Set(physical)
        primary = (groups.primary + physical).compactMap { byID[$0] }
        other = groups.other.filter { !visible.contains($0) }.compactMap { byID[$0] }
        hidden = groups.hidden.compactMap { byID[$0] }
    }
}
