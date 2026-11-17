import HopHardwareKit
import SwiftUI

struct CoolingView: View {
    @ObservedObject var controller: CoolingController
    let lang: AppLanguage
    var allowsFanControls = true
    @State private var draft = FanPolicy()

    init(controller: CoolingController, lang: AppLanguage, initialPolicy: FanPolicy? = nil, allowsFanControls: Bool = true) {
        self.controller = controller; self.lang = lang
        self.allowsFanControls = allowsFanControls
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

    private var visibleReason: HardwareReason? {
        controller.failure ?? (controller.snapshot.restorationPending ? .restoreFailed : controller.lastStopReason)
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
                if controller.hasReadings {
                    Text(t(.hardwareUnsupported)).font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            if allowsFanControls {
                ForEach(controller.snapshot.fans) { fan in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(t(.coolingFan)) \(fan.id + 1)")
                            Spacer()
                            Text("\(Int(fan.rpm.rounded())) rpm").monospacedDigit()
                        }
                        .font(Theme.mono(12))
                        HStack {
                            Text("\(Int(fan.minimum))–\(Int(fan.maximum)) rpm")
                            Spacer()
                            if offersFanControls {
                                Text(fan.manual && !controller.snapshot.active
                                     ? t(.coolingExternal) : title(controller.snapshot.policy.mode))
                            }
                        }
                        .font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                        if offersFanControls && draft.mode == .fixed {
                            HStack {
                                if Snapshot.active {
                                    Capsule().fill(Theme.chipBg).frame(height: 4)
                                } else {
                                Slider(value: Binding(
                                    get: { draft.targets[fan.id] ?? max(fan.minimum, min(fan.maximum, fan.rpm)) },
                                    set: { draft.targets[fan.id] = $0 }), in: fan.minimum...fan.maximum, step: 50)
                                }
                                Text("\(Int(draft.targets[fan.id] ?? max(fan.minimum, min(fan.maximum, fan.rpm))))")
                                    .font(Theme.mono(11)).frame(width: 48, alignment: .trailing)
                            }
                        }
                    }
                    .padding(12).background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if offersFanControls {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(FanPolicy.Mode.allCases, id: \.self) { mode in
                        Button {
                            draft.mode = mode
                            for fan in controller.snapshot.fans where draft.targets[fan.id] == nil {
                                draft.targets[fan.id] = max(fan.minimum, min(fan.maximum, fan.rpm))
                            }
                        } label: {
                            Text(title(mode)).font(Theme.mono(11)).frame(maxWidth: .infinity)
                                .padding(10).background(draft.mode == mode ? Theme.chipBg : Theme.rowBg,
                                    in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain).hoverHighlight(7)
                        .disabled(mode != .automatic && !controller.snapshot.supportsControl)
                    }
                }
                if draft.mode == .automatic {
                    Text(t(.coolingAutomaticHint)).font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if draft.mode == .curve {
                    Text(t(.coolingCurveHint)).font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if Snapshot.active {
                            Text("\(Int(draft.cool))").frame(maxWidth: .infinity)
                            Text("→")
                            Text("\(Int(draft.hot))").frame(maxWidth: .infinity)
                        } else {
                        TextField("°C", value: $draft.cool, format: .number.precision(.fractionLength(0)))
                        Text("→")
                        TextField("°C", value: $draft.hot, format: .number.precision(.fractionLength(0)))
                        }
                        Text("°C")
                    }
                    .font(Theme.mono(12)).textFieldStyle(.roundedBorder)
                }
            }
            if let reason = visibleReason {
                Text(t(CoolingCopy.key(reason))).font(Theme.mono(11))
                    .foregroundStyle(controller.snapshot.restorationPending ? Theme.accentOrange : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if offersFanControls || !allowsFanControls || controller.snapshot.restorationPending || controller.failure != nil {
                HStack(spacing: 10) {
                    if controller.serviceEnabled {
                        if offersFanControls {
                        Button(t(.coolingApply)) { controller.apply(draft) }
                            .disabled(controller.busy || (draft.mode != .automatic && !controller.snapshot.supportsControl))
                        }
                        Spacer()
                        Button(t(.hardwareApprove)) { controller.settings() }
                    } else {
                        Text(t(controller.approvalRequired ? .hardwareApprovalHint : .hardwareInstallHint))
                            .font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(t(controller.approvalRequired ? .hardwareApprove : .hardwareInstall)) {
                            if controller.approvalRequired { controller.settings() }
                            else { controller.install() }
                        }
                        .disabled(controller.busy)
                    }
                }
                .buttonStyle(.plain).font(Theme.mono(11))
            }
        }
        .foregroundStyle(Theme.textPrimary).padding(22)
        .frame(minWidth: 460, idealWidth: 500, maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.background)
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
