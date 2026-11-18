import HopHardwareKit
import SwiftUI

struct CoolingView: View {
    @ObservedObject var controller: CoolingController
    let lang: AppLanguage
    var allowsFanControls = true
    @State private var draft = FanPolicy()

    init(controller: CoolingController, lang: AppLanguage, initialPolicy: FanPolicy? = nil, allowsFanControls: Bool = true) {
        self.controller = controller; self.lang = lang; self.allowsFanControls = allowsFanControls
        _draft = State(initialValue: initialPolicy ?? controller.snapshot.policy)
    }

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
    private func title(_ mode: FanPolicy.Mode) -> String {
        t([.automatic: .coolingAutomatic, .maximum: .coolingMaximum,
           .fixed: .coolingFixed, .curve: .coolingCurve][mode]!)
    }
    private var offersFanControls: Bool {
        allowsFanControls && controller.snapshot.supportsControl && !controller.snapshot.fans.isEmpty
    }
    private var curveValid: Bool {
        draft.cool.isFinite && draft.hot.isFinite && (20...110).contains(draft.cool)
            && (25...120).contains(draft.hot) && draft.hot - draft.cool >= 5
    }
    private var showsDiagnostics: Bool {
        controller.snapshot.restorationPending || controller.failure != nil
            || controller.snapshot.stopCause != nil || controller.needsFanServiceUpdate
            || controller.fanAvailability == .unsupported || controller.fanAvailability == .unavailable
    }
    private var visibleReason: HardwareReason? {
        guard !controller.snapshot.restorationPending else { return .restoreFailed }
        return controller.failure ?? controller.lastStopReason
    }
    private func rpm(_ value: Double) -> String {
        guard value.isFinite, (0...30000).contains(value) else { return "—" }
        return "\(Int(value.rounded())) \(t(.coolingRPM))"
    }

    private func submit(debounce: Bool = false) {
        guard draft.mode != .curve || curveValid else { return }
        controller.apply(draft, debounce: debounce)
    }
    private func select(_ mode: FanPolicy.Mode) {
        draft.mode = mode
        let previous = draft.targets
        draft.targets = Dictionary(uniqueKeysWithValues: controller.snapshot.fans.map { fan in
            (fan.id, max(fan.minimum, min(fan.maximum, previous[fan.id] ?? fan.rpm)))
        })
        submit()
    }
    private func action(_ key: L10nKey, id: String, _ perform: @escaping () -> Void) -> some View {
        Group {
            if Snapshot.active { Text(t(key)).font(Theme.mono(11)) }
            else { CoolingActionButton(title: t(key), id: id, lang: lang, action: perform).frame(height: 22) }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "fan").foregroundStyle(Theme.accentBlue)
                Text(t(.coolingTitle)).font(Theme.mono(16))
                Spacer()
                if let temperature = controller.snapshot.temperature {
                    Text(String(format: "cpu %.0f °C", temperature)).font(Theme.mono(12))
                }
            }
            if allowsFanControls, !offersFanControls {
                if controller.hasReadings || controller.fanAvailability == .fanless {
                    Text(t(controller.fanAvailability == .fanless ? .coolingFanless
                           : controller.fanAvailability == .unsupported ? .hardwareUnsupported : .coolingReadFailed))
                        .font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else { ProgressView().controlSize(.small) }
            }
            if allowsFanControls {
                ForEach(controller.snapshot.fans) { fan in fanRow(fan) }
                if !controller.snapshot.fans.isEmpty {
                    Text(t(.coolingRPMHint)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if offersFanControls {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(FanPolicy.Mode.allCases, id: \.self) { mode in modeButton(mode) }
                }
                if let pending = controller.pendingFanPolicy {
                    Text("\(t(.coolingApplying)) \(title(pending.mode))")
                        .font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                }
                if draft.mode == .automatic {
                    Text(t(.coolingAutomaticHint)).font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if draft.mode == .curve { curveFields }
            }
            if let reason = visibleReason {
                Text(t(CoolingCopy.key(reason))).font(Theme.mono(11))
                    .foregroundStyle(controller.snapshot.restorationPending ? Theme.accentOrange : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !controller.serviceEnabled, controller.fanAvailability != .fanless || !allowsFanControls {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t(controller.approvalRequired ? .hardwareApprovalHint : .hardwareInstallHint))
                        .font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if controller.approvalRequired {
                        action(.hardwareApprove, id: "hop.cooling.service.approve") { controller.settings() }
                    } else {
                        action(.hardwareInstall, id: "hop.cooling.service.install") { controller.install() }
                            .disabled(controller.busy)
                    }
                }
            }
            if controller.needsFanServiceUpdate {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t(controller.blocksUpdates ? .hardwareUpdateWaiting : .hardwareUpdateNeeded))
                        .font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    action(.hardwareUpdateService, id: "hop.cooling.service.update") {
                        Task { await controller.updateFanService() }
                    }.disabled(controller.blocksUpdates)
                }
            }
            if showsDiagnostics {
                HStack(spacing: 14) {
                    if controller.serviceEnabled,
                       controller.snapshot.restorationPending || controller.fanAvailability == .unavailable {
                        action(.coolingRetry, id: "hop.cooling.retry") {
                            if controller.snapshot.restorationPending { controller.apply(.init(mode: .automatic)) }
                            else { Task { await controller.refresh() } }
                        }
                    }
                    action(.hardwareCopyDiagnostics, id: "hop.cooling.copy-diagnostic") {
                        Task { await controller.copyErrorDetails() }
                    }
                }
            }
        }
        .foregroundStyle(Theme.textPrimary).padding(22)
        .frame(minWidth: 460, idealWidth: 500, maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .onChange(of: controller.pendingFanPolicy) { _, value in
            if value == nil {
                if controller.snapshot.policy.mode == .automatic { draft.mode = .automatic }
                else { draft = controller.snapshot.policy }
            }
        }
    }

    private func fanRow(_ fan: FanReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(t(.coolingFan)) \(fan.id + 1)")
                Spacer()
                Text("\(t(.coolingCurrent)): \(rpm(fan.rpm))").monospacedDigit()
            }.font(Theme.mono(12))
            HStack {
                Text(verbatim: "\(t(.coolingRange)): \(Int(fan.minimum.rounded()))–\(rpm(fan.maximum))")
                Spacer()
                if fan.manual && !controller.snapshot.active { Text(t(.coolingExternal)) }
            }.font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
            if offersFanControls && draft.mode == .fixed {
                let target = draft.targets[fan.id] ?? max(fan.minimum, min(fan.maximum, fan.rpm))
                HStack {
                    Text(t(.coolingTarget))
                    Spacer()
                    Text(rpm(target)).monospacedDigit()
                }.font(Theme.mono(11))
                if Snapshot.active {
                    MiniSlider(value: .constant(Int(target.rounded())),
                        range: Int(fan.minimum)...max(Int(fan.minimum) + 1, Int(fan.maximum.rounded(.up))),
                        width: nil, showsNumber: false)
                } else {
                    CoolingSpeedSlider(value: Binding(get: { draft.targets[fan.id] ?? target }, set: { value in
                        guard value.isFinite else { return }
                        draft.targets[fan.id] = max(fan.minimum, min(fan.maximum, value.rounded()))
                        submit(debounce: true)
                    }), range: fan.minimum...fan.maximum, id: fan.id, label: t(.coolingTarget))
                    .frame(height: 18)
                    .disabled(!controller.serviceEnabled || controller.snapshot.restorationPending)
                }
            }
        }
        .padding(12).background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 8))
    }

    private func modeButton(_ mode: FanPolicy.Mode) -> some View {
        let selected = controller.shownFanMode == mode
        return Group {
            if Snapshot.active {
                HStack(spacing: 6) {
                    if selected, let check = CoolingActionButton.check {
                        Image(nsImage: check).renderingMode(.template).frame(width: 12, height: 12)
                    }
                    Text(title(mode)).font(Theme.mono(11))
                }.frame(maxWidth: .infinity, minHeight: 22)
            } else {
                CoolingActionButton(title: title(mode), id: "hop.cooling.mode." + mode.rawValue,
                    lang: lang, selected: selected, centered: true) { select(mode) }
                    .frame(maxWidth: .infinity, minHeight: 22)
            }
        }
        .padding(9).background(selected ? Theme.chipBg : Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .hoverHighlight(7)
        .disabled(!controller.serviceEnabled || (mode != .automatic
            && (controller.snapshot.restorationPending || controller.needsFanServiceUpdate)))
    }

    private var curveFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t(.coolingCurveHint)).font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 16) {
                curveField(.coolingFrom, value: $draft.cool)
                curveField(.coolingFullAt, value: $draft.hot)
            }
            if !curveValid {
                Text(t(.coolingInvalidCurve)).font(Theme.mono(10)).foregroundStyle(Theme.accentOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func curveField(_ label: L10nKey, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(t(label)).font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
            HStack {
                if Snapshot.active {
                    Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0))))
                        .frame(width: 75, alignment: .leading)
                }
                else {
                    TextField("°C", value: Binding(get: { value.wrappedValue }, set: { next in
                        value.wrappedValue = next; submit(debounce: true)
                    }), format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder).frame(width: 75)
                }
                Text("°C")
            }.font(Theme.mono(12))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CoolingWindowRoot: View {
    let controller: CoolingController
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @AppStorage(SettingsKey.appLanguage) private var language = "auto"
    @AppStorage(Theme.themeKey) private var theme = "auto"
    @State private var modulesRevision = 0

    private var content: some View {
        CoolingView(controller: controller, lang: L10n.resolve(language),
                    allowsFanControls: ModuleActivation.isOn("system"))
            .frame(width: CoolingWindow.contentWidth)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear.onAppear { onHeightChange(geometry.size.height) }
                    .onChange(of: geometry.size.height) { _, height in onHeightChange(height) }
            })
    }

    var body: some View {
        Group {
            if Snapshot.active { content }
            else { ScrollView { content } }
        }
        .frame(width: CoolingWindow.contentWidth)
        .background(Theme.background)
        .id("\(theme)-\(modulesRevision)")
        .onReceive(NotificationCenter.default.publisher(for: ModuleActivation.didChange)) { _ in modulesRevision += 1 }
    }
}

enum CoolingCopy {
    static func key(_ reason: HardwareReason) -> L10nKey {
        switch reason {
        case .battery: return .hardwareBattery
        case .thermal: return .hardwareThermal
        case .expired: return .hardwareExpired
        case .heartbeat, .disconnected: return .hardwareHeartbeat
        case .sensor: return .hardwareSensor
        case .restoreFailed: return .hardwarePending
        case .unsupported, .unavailable: return .hardwareUnsupported
        case .busy: return .hardwareBusy
        case .serviceApproval: return .hardwareApprovalHint
        case .serviceMissing: return .hardwareInstallHint
        case .unsignedBuild: return .hardwareSignedRequired
        case .stopped: return .coolingAutomatic
        default: return .hardwareFailure
        }
    }
}
