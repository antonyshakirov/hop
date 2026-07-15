import SwiftUI

/// System tab: compact metric rows with colored icons and meaning-driven
/// value highlighting. Polling runs only while the tab is on screen.
struct StatsView: View {
    @ObservedObject var stats: SystemStatsController
    let lang: AppLanguage

    @AppStorage("tempUnit") private var tempUnitRaw = "auto"
    @AppStorage("monitorDetailed") private var detailed = false
    // calm mode: only problems get color; the rainbow is opt-in
    @AppStorage("monitorColorful") private var colorful = false
    // chart window: how many minutes of history to show (1/5/10/30)
    @AppStorage("monitorWindowMin") private var monitorWindowMin = 5

    @AppStorage(Thresholds.tempYellowKey) private var tempYellow = Thresholds.tempYellowDefault
    @AppStorage(Thresholds.tempRedKey) private var tempRed = Thresholds.tempRedDefault
    @AppStorage(Thresholds.loadYellowKey) private var loadYellow = Thresholds.loadYellowDefault
    @AppStorage(Thresholds.loadRedKey) private var loadRed = Thresholds.loadRedDefault
    @AppStorage(Thresholds.memYellowKey) private var memYellow = Thresholds.memYellowDefault
    @AppStorage(Thresholds.memRedKey) private var memRed = Thresholds.memRedDefault
    @AppStorage(Thresholds.diskYellowKey) private var diskYellow = Thresholds.diskYellowDefault
    @AppStorage(Thresholds.diskRedKey) private var diskRed = Thresholds.diskRedDefault
    @AppStorage(Thresholds.battYellowKey) private var battYellow = Thresholds.battYellowDefault
    @AppStorage(Thresholds.battRedKey) private var battRed = Thresholds.battRedDefault

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    /// auto → follows the system region (US etc. — °F), otherwise an explicit choice
    private var useFahrenheit: Bool {
        switch tempUnitRaw {
        case "f": return true
        case "c": return false
        default: return Locale.current.measurementSystem == .us
        }
    }

    private func tempText(_ v: Double?) -> String {
        guard let v else { return "—" }
        let shown = useFahrenheit ? v * 9 / 5 + 32 : v
        return "\(Int(shown.rounded()))°"
    }

    var body: some View {
        let s = stats.sample
        let chartEnd = Date()
        let chartStart = chartEnd.addingTimeInterval(-Double(monitorWindowMin) * 60)
        VStack(spacing: detailed ? 12 : 10) {
            row(icon: "cpu", color: Theme.accentBlue, label: "cpu",
                value: loadAndTemp(s.cpuLoad, s.cpuTemp))
            if detailed {
                // both lines are shades of the metric's color; the 0–100 scale is shared (% and °C)
                SparklineCard(series: [
                    .init(label: t(.legendLoad), points: windowed(stats.history.cpuLoad, from: chartStart),
                          color: Theme.accentBlue, maxValue: 1),
                    .init(label: t(.legendTemp), points: windowed(stats.history.cpuTemp, from: chartStart),
                          color: Theme.graphShade(Theme.accentBlue), maxValue: 100),
                ], start: chartStart, end: chartEnd)
                .padding(.bottom, 6)
            }
            row(icon: "memorychip", color: Theme.accentPurple, label: "gpu",
                value: gpuValue(s))
            row(icon: "square.stack.3d.up", color: Theme.accentGreen, label: t(.statMemory),
                value: memValue(s))
            if detailed {
                SparklineCard(series: [
                    .init(label: t(.legendMemShare), points: windowed(stats.history.memShare, from: chartStart),
                          color: Theme.accentGreen, maxValue: 1),
                ], start: chartStart, end: chartEnd)
                .padding(.bottom, 6)
            }
            row(icon: "arrow.up.arrow.down", color: Theme.accentCyan, label: t(.statNetwork),
                value: netValue(s))
            if detailed {
                let downPoints = windowed(stats.history.netDown, from: chartStart)
                let upPoints = windowed(stats.history.netUp, from: chartStart)
                let peak = max(downPoints.map(\.v).max() ?? 0,
                               upPoints.map(\.v).max() ?? 0)
                SparklineCard(series: [
                    .init(label: "↓ \(t(.legendDown))", points: downPoints,
                          color: Theme.accentCyan, maxValue: max(peak, 1)),
                    .init(label: "↑ \(t(.legendUp))", points: upPoints,
                          color: Theme.graphShade(Theme.accentCyan), maxValue: max(peak, 1)),
                ], start: chartStart, end: chartEnd)
                .padding(.bottom, 6)
            }
            row(icon: "internaldrive", color: Theme.accentYellow, label: t(.statDisk),
                value: diskValue(s))
            if let b = s.battery {
                row(icon: batteryIcon(b), color: batteryColor(b), label: t(.statBattery),
                    value: batteryValue(b))
                if b.cycles != nil || b.healthPercent != nil {
                    row(icon: "heart.fill", color: Theme.accentRed, label: t(.statHealth),
                        value: healthValue(b))
                }
                if b.isCharging || b.adapterWatts != nil {
                    row(icon: "bolt.fill", color: Theme.accentOrange, label: t(.statPower),
                        value: powerValue(b))
                }
            }
            // time since the Mac last rebooted
            row(icon: "arrow.triangle.2.circlepath", color: Theme.textSecondary, label: t(.statReboot),
                value: Text(StatsFormatting.uptime(
                    s.uptime, day: t(.unitDay), hour: t(.unitHour), minute: t(.unitMin)
                )).foregroundColor(Theme.textSecondary))
        }
        .padding(.vertical, 4)
        .onAppear { stats.startPolling() }
        .onDisappear { stats.stopPolling() }
    }

    /// Slice of history within the window: points older than its start are not drawn.
    private func windowed(
        _ points: [SystemStatsController.HistoryPoint], from start: Date
    ) -> [SystemStatsController.HistoryPoint] {
        points.filter { $0.t >= start }
    }

    // MARK: - Row

    private func row(icon: String, color: Color, label: String, value: Text) -> some View {
        // rows are larger in chart mode: the metric must outweigh the chart
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: detailed ? 12 : 10))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(label)
                .font(Theme.mono(detailed ? 12 : 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 62, alignment: .leading)
            Spacer()
            value.font(Theme.mono(detailed ? 12 : 11))
        }
    }

    private var dot: Text {
        Text(" · ").foregroundColor(Theme.textTertiary)
    }

    // MARK: - Level-based highlighting

    // Color logic: green/gray-white — all fine, yellow — borderline, red — a problem.
    // Thresholds are configurable in system settings.
    private func loadColor(_ v: Double?) -> Color {
        guard let v else { return Theme.textTertiary }
        if v * 100 >= Double(loadRed) { return Theme.accentRed }
        if v * 100 >= Double(loadYellow) { return Theme.accentYellow }
        return Theme.textSecondary
    }

    private func tempColor(_ t: Double?) -> Color {
        guard let t else { return Theme.textTertiary }
        if t >= Double(tempRed) { return Theme.accentRed }
        if t >= Double(tempYellow) { return Theme.accentYellow }
        return colorful ? Theme.accentGreen : Theme.textSecondary
    }

    // MARK: - Values

    private func loadAndTemp(_ load: Double?, _ temp: Double?) -> Text {
        Text(StatsFormatting.percent(load)).foregroundColor(loadColor(load))
            + dot
            + Text(tempText(temp)).foregroundColor(tempColor(temp))
    }

    private func gpuValue(_ s: StatsSample) -> Text {
        // PMU chips have no dedicated GPU sensor — don't show a dash
        guard s.gpuTemp != nil else {
            return Text(StatsFormatting.percent(s.gpuLoad))
                .foregroundColor(loadColor(s.gpuLoad))
        }
        return loadAndTemp(s.gpuLoad, s.gpuTemp)
    }

    /// Memory colors by SWAP, not by "used": full RAM is normal on macOS.
    /// (used+swap)/RAM can exceed 100% — red at memRed (e.g. 150).
    private func memValue(_ s: StatsSample) -> Text {
        let pressureColor: Color = {
            guard let used = s.memUsed, let total = s.memTotal, total > 0 else {
                return Theme.textSecondary
            }
            let ratio = (used + (s.swapUsed ?? 0)) / total * 100
            if ratio >= Double(memRed) { return Theme.accentRed }
            if ratio >= Double(memYellow) { return Theme.accentYellow }
            return colorful ? Theme.accentGreen : Theme.textSecondary
        }()
        // the main figure = used + swap: total memory footprint is visible,
        // and with swap it exceeds RAM size (e.g. "30 / 24 GB")
        let footprint = (s.memUsed ?? 0) + (s.swapUsed ?? 0)
        var text = Text(StatsFormatting.gb(footprint)).foregroundColor(pressureColor)
            + Text(" / \(StatsFormatting.gb(s.memTotal)) \(t(.unitGB))").foregroundColor(Theme.textSecondary)
        // if there is swap — clarify how much of it went to disk
        if let swap = s.swapUsed, swap > 50_000_000 {
            text = text + Text("  swap \(StatsFormatting.gb(swap))").foregroundColor(pressureColor)
        }
        return text
    }

    // both arrows use informational colors (not status): ↓ blue, ↑ cyan
    private func netValue(_ s: StatsSample) -> Text {
        Text("↓ \(speedText(s.netDown))").foregroundColor(colorful ? Theme.accentBlue : Theme.textSecondary)
            + Text("   ")
            + Text("↑ \(speedText(s.netUp))").foregroundColor(colorful ? Theme.accentCyan : Theme.textSecondary)
    }

    private func diskValue(_ s: StatsSample) -> Text {
        guard let free = s.diskFree, let total = s.diskTotal, total > 0 else {
            return Text("—").foregroundColor(Theme.textTertiary)
        }
        let usedShare = (total - free) / total
        let usedPercent = Int((usedShare * 100).rounded())
        // the disk has its own thresholds: below diskYellow is normal
        let diskColor: Color = usedShare * 100 >= Double(diskRed)
            ? Theme.accentRed
            : usedShare * 100 >= Double(diskYellow) ? Theme.accentYellow : Theme.textSecondary
        // used/total — the convention in system monitors
        var result = Text("\(StatsFormatting.gb(total - free))/\(StatsFormatting.gb(total)) \(t(.unitGB))")
            .foregroundColor(Theme.textSecondary)
            + dot
            + Text("\(usedPercent)%").foregroundColor(diskColor)
        if let t = s.ssdTemp {
            result = result + dot
                + Text(tempText(t)).foregroundColor(tempColor(t))
        }
        return result
    }

    private func batteryIcon(_ b: BatteryInfo) -> String {
        if b.isCharging { return "battery.100percent.bolt" }
        guard let p = b.percent else { return "battery.100percent" }
        switch p {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func batteryColor(_ b: BatteryInfo) -> Color {
        guard let p = b.percent else { return Theme.textTertiary }
        if p <= battRed { return Theme.accentRed }
        if p <= battYellow { return Theme.accentYellow }
        return colorful ? Theme.accentGreen : Theme.textSecondary
    }

    private func batteryValue(_ b: BatteryInfo) -> Text {
        let percent: Text = b.percent.map {
            Text("\($0)%").foregroundColor(batteryColor(b))
        } ?? Text("—").foregroundColor(Theme.textTertiary)
        return percent + dot
            + Text(tempText(b.tempC)).foregroundColor(tempColor(b.tempC))
            + (b.isCharging
                ? dot + Text(t(.statCharging)).foregroundColor(colorful ? Theme.accentGreen : Theme.textSecondary)
                : Text(""))
    }

    private func healthValue(_ b: BatteryInfo) -> Text {
        var parts: [Text] = []
        if let h = b.healthPercent {
            parts.append(
                Text("\(h)%")
                    .foregroundColor(h < 80 ? Theme.accentYellow : Theme.textSecondary)
            )
        }
        if let c = b.cycles {
            parts.append(Text("\(c) \(t(.statCycles))").foregroundColor(Theme.textSecondary))
        }
        guard var result = parts.first else {
            return Text("—").foregroundColor(Theme.textTertiary)
        }
        for part in parts.dropFirst() {
            result = result + dot + part
        }
        return result
    }

    private func powerValue(_ b: BatteryInfo) -> Text {
        var parts: [Text] = []
        if let a = b.adapterWatts {
            parts.append(Text("\(t(.statAdapter)) \(a)\(t(.unitW))").foregroundColor(Theme.textSecondary))
        }
        if let w = b.batteryWatts, abs(w) > 0.5 {
            parts.append(
                w > 0
                    ? Text("\(t(.statCharge)) +\(wattsText(w))").foregroundColor(colorful ? Theme.accentGreen : Theme.textSecondary)
                    : Text("\(t(.statDraw)) \(wattsText(w))").foregroundColor(colorful ? Theme.accentOrange : Theme.textSecondary)
            )
        }
        guard var result = parts.first else {
            return Text("—").foregroundColor(Theme.textTertiary)
        }
        for part in parts.dropFirst() {
            result = result + dot + part
        }
        return result
    }

    // MARK: - Localized units

    private func speedText(_ v: Double?) -> String {
        guard let v else { return "—" }
        if v >= 1_048_576 { return String(format: "%.1f %@", v / 1_048_576, t(.unitMBs)) }
        if v >= 1024 { return String(format: "%.0f %@", v / 1024, t(.unitKBs)) }
        return "\(Int(v)) \(t(.unitBs))"
    }

    private func agoText(_ uptime: TimeInterval?) -> String {
        let duration = StatsFormatting.uptime(
            uptime, day: t(.unitDay), hour: t(.unitHour), minute: t(.unitMin)
        )
        return t(.agoFormat).replacingOccurrences(of: "%@", with: duration)
    }

    private func wattsText(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.0f%@", abs(v), t(.unitW))
    }
}
