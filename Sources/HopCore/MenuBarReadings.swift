import Foundation

public enum MenuBarMetric: String, CaseIterable, Identifiable {
    case timer, tracker, cpu, gpu, cpuTemperature, gpuTemperature
    case memory, swap, disk, diskTemperature, download, upload, battery, batteryTemperature
    case batteryHealth, batteryCycles, batteryPower, adapterPower, uptime
    case awake, vpn, torrents, outputMix, inputMix

    public var id: String { rawValue }

    public var module: String {
        switch self {
        case .timer: return "timer"
        case .tracker: return "tracker"
        case .awake: return "awake"
        case .vpn: return "vpn"
        case .torrents: return "torrent"
        case .outputMix, .inputMix: return "sound"
        default: return "system"
        }
    }

    public var symbol: String {
        switch self {
        case .timer: return "timer"
        case .tracker: return "record.circle"
        case .cpu: return "cpu"
        case .gpu: return "square.3.layers.3d"
        case .cpuTemperature, .gpuTemperature, .diskTemperature, .batteryTemperature: return "thermometer.medium"
        case .memory: return "memorychip"
        case .swap: return "arrow.left.arrow.right"
        case .disk: return "internaldrive"
        case .download: return "arrow.down"
        case .upload: return "arrow.up"
        case .battery: return "battery.100percent"
        case .batteryHealth: return "heart"
        case .batteryCycles: return "arrow.triangle.2.circlepath"
        case .batteryPower, .adapterPower: return "bolt"
        case .uptime: return "clock.arrow.circlepath"
        case .awake: return "cup.and.saucer"
        case .vpn: return "network.badge.shield.half.filled"
        case .torrents: return "arrow.down.circle"
        case .outputMix: return "speaker.wave.2"
        case .inputMix: return "mic"
        }
    }
}

public struct MenuBarReadings: Equatable {
    public enum Layout: String { case rotating, together }

    public var order = MenuBarMetric.allCases
    public var enabled: Set<MenuBarMetric> = []
    public var layout: Layout = .rotating
    public var detailed = false

    public init() {}

    public static func decode(_ raw: String) -> Self {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Self() }
        var result = Self()
        var seen: Set<MenuBarMetric> = []
        result.order = ((object["order"] as? [String] ?? []).compactMap(MenuBarMetric.init(rawValue:))
            + MenuBarMetric.allCases).filter { seen.insert($0).inserted }
        result.enabled = Set((object["enabled"] as? [String] ?? []).compactMap(MenuBarMetric.init(rawValue:)))
        result.layout = Layout(rawValue: object["layout"] as? String ?? "") ?? .rotating
        result.detailed = object["detailed"] as? Bool ?? false
        return result
    }

    public var encoded: String {
        let object: [String: Any] = ["order": order.map(\.rawValue),
            "enabled": enabled.map(\.rawValue).sorted(), "layout": layout.rawValue, "detailed": detailed]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    public mutating func move(_ metric: MenuBarMetric, by offset: Int) {
        guard let index = order.firstIndex(of: metric), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
    }

    public func visible(inactive: Set<String>, timer: Bool, tracker: Bool) -> [MenuBarMetric] {
        order.filter { metric in
            guard !inactive.contains(metric.module) else { return false }
            switch metric {
            case .timer: return timer
            case .tracker: return tracker
            default: return enabled.contains(metric)
            }
        }
    }

    public func rotates(texts: [String]) -> Bool {
        layout == .rotating || texts.joined(separator: "  ").count > 54
    }
}
