import AppKit
import HopCore

struct MenuBarReading {
    let metric: MenuBarMetric
    let value: String
    let label: String

    var text: String { label.isEmpty ? value : "\(label) \(value)" }
    var symbol: String { metric.symbol }

    func tooltip(lang: AppLanguage) -> String {
        if metric == .outputMix || metric == .inputMix {
            return Self.title(metric, lang: lang) + ": " + L10n.t(value == "✓" ? .barRunning : .barStopped, lang)
        }
        if metric == .memory {
            let parts = value.split(separator: "/", maxSplits: 1)
            if parts.count == 2 {
                return String(format: L10n.t(.barMemoryTooltip, lang),
                    String(parts[0]), String(parts[1]).replacingOccurrences(of: " GB", with: "\u{00A0}GB"))
            }
        }
        return Self.title(metric, lang: lang) + ": " + value
    }

    static let maximumReadingWidth: CGFloat = 420
    static let mixerLeadingGap: CGFloat = 6
    static var barFont: NSFont { NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) }

    static func mixerLegend(lang: AppLanguage) -> String {
        "✓\u{00A0}" + L10n.t(.barRunning, lang) + " ·\u{00A0}—\u{00A0}" + L10n.t(.barStopped, lang)
    }

    static func shouldRotate(_ texts: [String], settings: MenuBarReadings) -> Bool {
        if settings.rotates(texts: texts) { return true }
        let text = texts.joined(separator: "  ") as NSString
        return text.size(withAttributes: [.font: barFont]).width + 8 > maximumReadingWidth
    }

    @MainActor
    static func live(_ metric: MenuBarMetric, model: AppModel, detailed: Bool,
                     lang: AppLanguage, temperatureUnit: String) -> Self {
        guard ModuleActivation.isOn(metric.module) else {
            return Self(metric: metric, value: "—", label: detailed ? title(metric, lang: lang) : "")
        }
        let value: String
        switch metric {
        case .timer:
            let engine = model.engine
            let running = engine.state == .running || engine.state == .paused
            value = running ? TimeFormatting.short(engine.isStopwatch ? engine.elapsed : engine.remaining) : "—"
        case .tracker:
            value = model.tracker.isTracking
                ? model.tracker.engine.activeTaskID.map { TimeFormatting.short(model.tracker.engine.today(taskID: $0)) } ?? "—" : "—"
        case .awake:
            value = model.keepAwake.isActive ? (model.keepAwake.remaining.map(TimeFormatting.short) ?? "∞") : "—"
        case .vpn:
            value = model.vpn.mark.map { $0 == .stalled ? "!" : "✓" } ?? "—"
        case .torrents:
            let active = model.torrent.torrents.filter { !($0.optimisticPaused ?? $0.pausedByPolicy) && $0.stats?.state == .live && $0.stats?.finished == false }
            let samples = active.compactMap(\.stats)
            let total = samples.reduce(0.0) { $0 + Double(max(0, $1.totalBytes)) }
            let progress = samples.reduce(0.0) { $0 + Double(max(0, min($1.progressBytes, $1.totalBytes))) }
            value = total > 0 ? "\(active.count) · " + String(format: "%.0f%%", progress / total * 100) : "—"
        case .outputMix: value = model.soundMixer.running ? "✓" : "—"
        case .inputMix: value = model.soundCallMix.running ? "✓" : "—"
        default:
            return sensor(metric, sample: model.stats.sample, detailed: detailed, lang: lang, temperatureUnit: temperatureUnit)
        }
        return Self(metric: metric, value: value, label: detailed ? title(metric, lang: lang) : "")
    }

    static func title(_ metric: MenuBarMetric, lang: AppLanguage) -> String {
        func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
        switch metric {
        case .timer: return ModulePresentation.titleKey("timer").map(t) ?? "timer"
        case .tracker: return t(.trackerLabel)
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .cpuTemperature: return "CPU · " + t(.legendTemp)
        case .gpuTemperature: return "GPU · " + t(.legendTemp)
        case .memory: return t(.statMemory)
        case .swap: return t(.barSwap)
        case .disk: return t(.barDiskFree)
        case .diskTemperature: return t(.statDisk) + " \u{00B7} " + t(.legendTemp)
        case .download: return t(.legendDown)
        case .upload: return t(.legendUp)
        case .battery: return t(.statBattery)
        case .batteryTemperature: return t(.statBattery) + " · " + t(.legendTemp)
        case .batteryHealth: return t(.statHealth)
        case .batteryCycles: return t(.barCycles)
        case .batteryPower: return t(.statPower)
        case .adapterPower: return t(.barAdapter)
        case .uptime: return t(.statReboot)
        case .awake: return ModulePresentation.titleKey("awake").map(t) ?? "awake"
        case .vpn: return t(.vpnLabel)
        case .torrents: return t(.torrentLabel)
        case .outputMix: return t(.barAppMixerState)
        case .inputMix: return t(.barCallMixerState)
        }
    }

    static func sensor(_ metric: MenuBarMetric, sample s: StatsSample, detailed: Bool,
                       lang: AppLanguage, temperatureUnit: String) -> Self {
        func finite(_ value: Double?) -> Double? { value.flatMap { $0.isFinite ? $0 : nil } }
        func positive(_ value: Double?) -> Double? { finite(value).flatMap { $0 >= 0 ? $0 : nil } }
        func percent(_ value: Double?) -> String {
            guard let value = positive(value), value <= 1 else { return "—" }
            return String(format: "%.0f%%", value * 100)
        }
        func integer(_ value: Int?, upper: Int = Int.max) -> String {
            guard let value, (0...upper).contains(value) else { return "—" }
            return String(value)
        }
        func bytes(_ value: Double?, binary: Bool) -> String {
            guard let value = positive(value) else { return "—" }
            return String(format: "%.1f GB", value / (binary ? 1_073_741_824 : 1_000_000_000))
        }
        func speed(_ value: Double?) -> String {
            guard let value = positive(value) else { return "—" }
            if value >= 1_000_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
            if value >= 1_000 { return String(format: "%.0f KB/s", value / 1_000) }
            return String(format: "%.0f B/s", value)
        }
        func temperature(_ value: Double?) -> String {
            guard let value = finite(value), (-50...200).contains(value) else { return "—" }
            let fahrenheit = temperatureUnit == "f"
                || (temperatureUnit == "auto" && Locale.current.measurementSystem == .us)
            return String(format: "%.0f°%@", fahrenheit ? value * 9 / 5 + 32 : value, fahrenheit ? "F" : "C")
        }
        let value: String
        switch metric {
        case .cpu: value = percent(s.cpuLoad)
        case .gpu: value = percent(s.gpuLoad)
        case .cpuTemperature: value = temperature(s.cpuTemp)
        case .gpuTemperature: value = temperature(s.gpuTemp)
        case .memory:
            if let used = positive(s.memUsed), let total = positive(s.memTotal), total > 0, used <= total {
                value = String(format: "%.1f/%.0f GB", used / 1_073_741_824, total / 1_073_741_824)
            } else { value = "—" }
        case .swap: value = bytes(s.swapUsed, binary: true)
        case .disk: value = bytes(s.diskFree, binary: false)
        case .diskTemperature: value = temperature(s.ssdTemp)
        case .download: value = speed(s.netDown)
        case .upload: value = speed(s.netUp)
        case .battery:
            value = integer(s.battery?.percent, upper: 100).appending(s.battery?.percent.map { (0...100).contains($0) ? "%" : "" } ?? "")
                + (s.battery?.isCharging == true ? " ⚡" : "")
        case .batteryTemperature: value = temperature(s.battery?.tempC)
        case .batteryHealth:
            value = s.battery?.healthPercent.flatMap { (0...100).contains($0) ? "\($0)%" : nil } ?? "—"
        case .batteryCycles: value = integer(s.battery?.cycles)
        case .batteryPower:
            value = finite(s.battery?.batteryWatts).map { String(format: "%+.1f W", $0) } ?? "—"
        case .adapterPower:
            value = s.battery?.adapterWatts.flatMap { $0 > 0 ? "\($0) W" : nil } ?? "—"
        case .uptime:
            value = positive(s.uptime).flatMap { $0 < 1e12 ? StatsFormatting.uptime($0) : nil } ?? "—"
        default: value = "—"
        }
        return Self(metric: metric, value: value, label: detailed ? title(metric, lang: lang) : (metric == .download ? "\u{2193}" : metric == .upload ? "\u{2191}" : ""))
    }
}
