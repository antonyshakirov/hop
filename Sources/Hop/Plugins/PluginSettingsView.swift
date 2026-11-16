import SwiftUI
import UniformTypeIdentifiers
import HopPluginAPI

struct PluginSettingsView: View {
    @ObservedObject var manager: PluginManager
    let lang: AppLanguage
    @State private var approving: PluginRecord?
    @State private var query = ""
    private func t(_ key: PluginText) -> String { PluginCopy.text(key, lang) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t(.overview))
                .font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(t(.importFile), action: importFile).buttonStyle(.plain).hoverDim()
                Spacer()
            }
            if manager.error != nil {
                Text(t(manager.error == PluginError.memoryLimit.rawValue ? .memoryError : .error)).font(Theme.mono(11)).foregroundStyle(Theme.accentOrange).fixedSize(horizontal: false, vertical: true)
            }
            if manager.records.isEmpty { SettingsCard { Text(t(.empty)).foregroundStyle(Theme.textSecondary) } }
            if !manager.records.isEmpty {
                SteadyField(text: $query, placeholder: L10n.t(.searchLabel, lang))
                    .padding(8).background(Theme.fieldBg).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if !manager.records.isEmpty && PluginInstalledQuery.filter(manager.records, query: query).isEmpty {
                SettingsCard { Text(t(.noMatches)).foregroundStyle(Theme.textSecondary) }
            }
            ForEach(PluginInstalledQuery.filter(manager.records, query: query)) { record in
                SettingsCard {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.package.manifest.name).font(Theme.mono(13, weight: .semibold)).lineLimit(2)
                            Text(record.package.manifest.description).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary).lineLimit(3)
                            Text(metadata(record))
                                .font(Theme.mono(10)).foregroundStyle(Theme.textTertiary).lineLimit(2)
                            Text(status(record)).font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                        }.fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 10)
                        PluginInstalledActions(record: record, active: manager.active.contains(record.id), lang: lang,
                            requestEnable: { approving = record }, disable: { manager.disable(record.id) })
                            .fixedSize()
                    }
                    DisclosureGroup(t(.permissions)) {
                        ForEach(record.package.manifest.capabilities, id: \.self) { capability in
                            Text(PluginCopy.capability(capability, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    ForEach(record.package.manifest.settings, id: \.key) { descriptor in setting(record, descriptor) }
                    HStack {
                        Spacer()
                        PluginRemoveButton(id: record.id, name: record.package.manifest.name, lang: lang,
                                           action: { manager.remove(record.id) })
                            .frame(width: 24, height: 24)
                    }
                }
            }
            if !manager.active.isEmpty { Button(t(.recovery)) { manager.disableAll() }.buttonStyle(.plain).hoverDim() }
            PluginLibraryLinks(lang: lang)
        }
        .font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
        .sheet(item: $approving) { record in
            PluginApprovalView(record: record, lang: lang, cancel: { approving = nil }, approve: {
                manager.approve(record.id, digest: record.digest, capabilities: Set(record.package.manifest.capabilities))
                approving = nil
            })
        }
    }
    private func metadata(_ record: PluginRecord) -> String {
        let origin: String
        if record.origin == "local" { origin = t(.local) }
        else { origin = URL(string: record.origin)?.host ?? t(.catalog) }
        return [record.package.manifest.version, record.package.manifest.author, origin].joined(separator: " · ")
    }
    private func status(_ record: PluginRecord) -> String {
        if record.lastError == PluginError.memoryLimit.rawValue { return t(.memoryError) }
        if record.package.compatibilityIssue != nil { return t(.incompatible) }
        if record.quarantinedDigest != nil || (record.wantedEnabled && !manager.active.contains(record.id)) { return t(.paused) }
        return t(manager.active.contains(record.id) ? .running : .off)
    }
    @ViewBuilder private func setting(_ record: PluginRecord, _ descriptor: PluginSetting) -> some View {
        let value = record.settings[descriptor.key] ?? descriptor.default
        HStack {
            Text(descriptor.label).font(Theme.mono(11))
            Spacer(minLength: 12)
            switch descriptor.type {
            case "boolean":
                Theme.MiniSwitch(isOn: Binding(get: { value == .bool(true) }, set: { manager.setting(record.id, key: descriptor.key, value: .bool($0)) }))
            case "integer":
                Stepper(value: Binding(get: { Int(value.number ?? 0) }, set: { manager.setting(record.id, key: descriptor.key, value: .number(Double($0))) }),
                        in: Int(descriptor.min ?? -1_000_000_000)...Int(descriptor.max ?? 1_000_000_000)) {
                    Text(String(Int(value.number ?? 0))).monospacedDigit()
                }.frame(width: 120)
            default:
                PluginStringSetting(value: value.string ?? "", label: descriptor.label) {
                    manager.setting(record.id, key: descriptor.key, value: .string($0))
                }.frame(maxWidth: 220)
            }
        }
    }
    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "hopplugin") ?? UTType(importedAs: "com.antonshakirov.hopplugin", conformingTo: .json), .json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= 1_048_576 else { throw PluginError.invalidPackage }
                manager.install(try Data(contentsOf: url), origin: "local")
            } catch { manager.error = PluginError.invalidPackage.rawValue }
        }
    }
}

struct PluginStringSetting: View {
    let value: String
    let label: String
    let commit: (String) -> Void
    @State private var draft: String
    @State private var submitted: String
    @State private var focused = false
    init(value: String, label: String, commit: @escaping (String) -> Void) {
        self.value = value; self.label = label; self.commit = commit
        _draft = State(initialValue: value); _submitted = State(initialValue: value)
    }
    var body: some View {
        SteadyField(text: $draft, placeholder: label, focus: $focused,
                    onSubmit: apply, onEndEditing: apply, onCancel: { draft = value; focused = false })
            .padding(.horizontal, 8).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.fieldBg))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.divider, lineWidth: 1))
            .onChange(of: value) { _, newValue in
                submitted = newValue
                if !focused { draft = newValue }
            }
    }
    private func apply() {
        guard draft != submitted else { return }
        submitted = draft
        commit(draft)
    }
}

struct PluginInstalledActions: View {
    let record: PluginRecord
    let active: Bool
    let lang: AppLanguage
    let requestEnable: () -> Void
    let disable: () -> Void
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            PluginEnableToggle(enabled: record.wantedEnabled, available: record.package.compatibilityIssue == nil || record.wantedEnabled,
                name: record.package.manifest.name, id: record.id, change: { enabled in
                    if enabled { requestEnable() } else { disable() }
                })
                .fixedSize()
                .help(PluginCopy.text(record.wantedEnabled ? .disable : .enable, lang))
            if record.wantedEnabled && !active {
                PluginActionButton(title: PluginCopy.text(.enable, lang), action: requestEnable, bordered: false,
                                   accessibilityID: "hop.plugins.retry." + record.id)
                    .fixedSize()
                    .disabled(record.package.compatibilityIssue != nil)
            }
        }
    }
}

struct PluginEnableToggle: NSViewRepresentable {
    let enabled: Bool
    let available: Bool
    let name: String
    let id: String
    let change: (Bool) -> Void
    final class Coordinator: NSObject {
        var change: (Bool) -> Void
        init(change: @escaping (Bool) -> Void) { self.change = change }
        @objc func changed(_ sender: NSSwitch) { change(sender.state == .on) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(change: change) }
    func makeNSView(context: Context) -> NSSwitch {
        let control = NSSwitch()
        control.controlSize = .mini
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        return control
    }
    func updateNSView(_ control: NSSwitch, context: Context) {
        context.coordinator.change = change
        control.state = enabled ? .on : .off
        control.isEnabled = available && context.environment.isEnabled
        control.identifier = NSUserInterfaceItemIdentifier("hop.plugins.toggle." + id)
        control.setAccessibilityIdentifier("hop.plugins.toggle." + id)
        control.setAccessibilityLabel(name)
    }
}

struct PluginApprovalView: View {
    let record: PluginRecord
    let lang: AppLanguage
    let cancel: () -> Void
    let approve: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(record.package.manifest.name).font(Theme.mono(17, weight: .semibold))
            Text(PluginCopy.text(.permissions, lang)).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
            ForEach(record.package.manifest.capabilities, id: \.self) { capability in
                Text("• " + PluginCopy.capability(capability, lang)).font(Theme.mono(12))
            }
            HStack {
                PluginActionButton(title: PluginCopy.text(.cancel, lang), action: cancel, bordered: false,
                                   accessibilityID: "hop.plugins.cancel", keyEquivalent: "\u{1b}")
                Spacer()
                PluginActionButton(title: PluginCopy.text(.approve, lang), action: approve, bordered: false,
                                   accessibilityID: "hop.plugins.approve", keyEquivalent: "\r")
            }.padding(.top, 8)
        }.padding(24).frame(width: 430).background(Theme.background).foregroundStyle(Theme.textPrimary)
    }
}
