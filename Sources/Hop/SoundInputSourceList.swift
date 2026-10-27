import HopCore

struct SoundInputListSource: Identifiable {
    let id: SoundInputSourceID
    let name: String
    var available: Bool
    var isVirtual = false
}

@MainActor
struct SoundInputSourceList {
    let primary: [SoundInputListSource]
    let other: [SoundInputListSource]
    let hidden: [SoundInputListSource]

    init(call: SoundCallMixController, devices: [SoundDevice],
         applications: [(id: String, name: String, available: Bool)]) {
        var sources = devices.map { SoundInputListSource(id: .device($0.uid), name: $0.name, available: true, isVirtual: $0.isVirtual) }
        sources += applications.map { SoundInputListSource(id: .application($0.id), name: $0.name, available: $0.available) }
        var seen = Set(sources.map(\.id))
        let retained = Set(call.sourceList.names.keys)
            .union(call.microphones.filter { $0.value.active }.keys.map(SoundInputSourceID.device))
            .union(call.applications.filter { $0.value.active }.keys.map(SoundInputSourceID.application))
        for id in retained.sorted(by: { $0.kind + $0.value < $1.kind + $1.value }) where seen.insert(id).inserted {
            sources.append(.init(id: id, name: call.sourceList.names[id] ?? id.value, available: false))
        }
        let groups = call.sourceList.groups(sources.map(\.id), selected: Set(sources.filter { call.sourceSelected($0.id) }.map(\.id)))
        let byID = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        primary = groups.primary.compactMap { byID[$0] }
        other = groups.other.compactMap { byID[$0] }
        hidden = groups.hidden.compactMap { byID[$0] }
    }
}
