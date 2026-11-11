import Combine
import HopCore
import SwiftUI

struct MenuBarSettingsView: View {
    @EnvironmentObject private var model: AppModel
    let lang: AppLanguage
    @AppStorage(SettingsKey.menuBarReadings) private var raw = ""
    @AppStorage(SettingsKey.showMenuBarCountdown) private var timer = true
    @AppStorage(SettingsKey.trackerTimeInBar) private var tracker = false
    @AppStorage(SettingsKey.menuBarIconOnly) private var iconOnly = false
    @AppStorage("tempUnit") private var temperatureUnit = "auto"
    @State private var sampleRevision = 0
    @State private var isVisible = false

    private var settings: MenuBarReadings { MenuBarReadings.decode(raw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    private func update(_ change: (inout MenuBarReadings) -> Void) {
        var next = settings
        change(&next)
        raw = next.encoded
    }

    private func selection(_ metric: MenuBarMetric) -> Binding<Bool> {
        Binding(get: {
            if metric == .timer { return timer }
            if metric == .tracker { return tracker }
            return settings.enabled.contains(metric)
        }, set: { enabled in
            if metric == .timer { timer = enabled }
            else if metric == .tracker { tracker = enabled }
            else { update { if enabled { $0.enabled.insert(metric) } else { $0.enabled.remove(metric) } } }
        })
    }

    var body: some View {
        let rows = settings.order.enumerated().map { (index: $0.offset, metric: $0.element, reading: currentReading($0.element)) }
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                HStack {
                    Text(t(.menuBarIconOnly)).font(Theme.mono(12))
                    Spacer()
                    Theme.MiniSwitch(isOn: $iconOnly)
                }
                SettingsRule()
                HStack(spacing: 6) {
                    layoutButton(.rotating, title: t(.barRotating))
                    layoutButton(.together, title: t(.barTogether))
                }
                .disabled(iconOnly)
                HStack {
                    Text(t(.barDetailed)).font(Theme.mono(12))
                    Spacer()
                    Theme.MiniSwitch(isOn: Binding(get: { settings.detailed }, set: { value in update { $0.detailed = value } }))
                }
                .disabled(iconOnly)
                Text(t(.barHint))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                preview
            }
            SettingsCard(spacing: 8) {
                ForEach(rows, id: \.metric) { index, metric, reading in
                    if index > 0 { SettingsRule() }
                    HStack(spacing: 10) {
                        Image(systemName: metric.symbol)
                            .frame(width: 18)
                            .foregroundStyle(Theme.textSecondary)
                        Button { selection(metric).wrappedValue.toggle() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selection(metric).wrappedValue ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selection(metric).wrappedValue ? Theme.accentGreen : Theme.textSecondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(MenuBarReading.title(metric, lang: lang))
                                        .font(Theme.mono(12))
                                        .fixedSize(horizontal: false, vertical: true)
                                    if metric == .outputMix || metric == .inputMix {
                                        Text(MenuBarReading.mixerLegend(lang: lang))
                                            .font(Theme.mono(9))
                                            .foregroundStyle(Theme.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityValue(selection(metric).wrappedValue ? t(.soundEnabled) : t(.soundDisabled))
                        .accessibilityIdentifier("menubar.reading.\(metric.rawValue)")
                        Spacer(minLength: 4)
                        Text(reading.value)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: 80, alignment: .trailing)
                            .help(reading.tooltip(lang: lang))
                        Image(systemName: "eye.slash")
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 14)
                            .opacity(ModuleActivation.inactiveModules().contains(metric.module) ? 1 : 0)
                            .accessibilityHidden(!ModuleActivation.inactiveModules().contains(metric.module))
                        Button { update { $0.move(metric, by: -1) } } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                            .accessibilityLabel("↑ " + MenuBarReading.title(metric, lang: lang))
                        Button { update { $0.move(metric, by: 1) } } label: { Image(systemName: "chevron.down") }
                            .disabled(index == settings.order.count - 1)
                            .accessibilityLabel("↓ " + MenuBarReading.title(metric, lang: lang))
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 26)
                }
            }
            .disabled(iconOnly)
            .opacity(iconOnly ? 0.45 : 1)
        }
        .foregroundStyle(Theme.textPrimary)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .onReceive(model.stats.$sample) { _ in if isVisible { sampleRevision &+= 1 } }
        .onReceive(model.barChanged.throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)) { _ in
            if isVisible { sampleRevision &+= 1 }
        }
    }

    private func currentReading(_ metric: MenuBarMetric) -> MenuBarReading {
        MenuBarReading.live(metric, model: model, detailed: false, lang: lang, temperatureUnit: temperatureUnit)
    }

    private func layoutButton(_ layout: MenuBarReadings.Layout, title: String) -> some View {
        Button { update { $0.layout = layout } } label: {
            Text(title)
                .font(Theme.mono(12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(settings.layout == layout ? Theme.chipBg : Theme.rowBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(settings.layout == layout ? [.isSelected] : [])
    }

    private var preview: some View {
        let metrics = settings.visible(inactive: ModuleActivation.inactiveModules(),
            timer: timer && (model.engine.state == .running || model.engine.state == .paused),
            tracker: tracker && model.tracker.isTracking)
        let readings = metrics.map {
            MenuBarReading.live($0, model: model, detailed: settings.detailed,
                lang: lang, temperatureUnit: temperatureUnit).text
        }
        let text = iconOnly ? "" : (MenuBarReading.shouldRotate(readings, settings: settings) ? readings.first ?? "" : readings.joined(separator: "  "))
        return HStack(spacing: 8) {
            Image(nsImage: MenuBarIcon.plainDialTemplate)
            Text(text).font(Theme.mono(12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("menubar.preview")
        .id(sampleRevision)
    }
}
