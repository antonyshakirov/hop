import SwiftUI
import UniformTypeIdentifiers
import HopPluginAPI

struct PluginSettingsView: View {
    @ObservedObject var manager: PluginManager
    let lang: AppLanguage
    @State private var approving: PluginRecord?
    private func t(_ key: PluginText) -> String { PluginCopy.text(key, lang) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(t(.importFile), action: importFile)
                Button(t(.catalog)) { Task { await manager.refreshCatalog() } }.disabled(manager.busy)
                Spacer()
            }
            if manager.error != nil {
                Text(t(manager.error == PluginError.memoryLimit.rawValue ? .memoryError : .error)).font(Theme.mono(11)).foregroundStyle(Theme.accentOrange).fixedSize(horizontal: false, vertical: true)
            }
            if manager.records.isEmpty { SettingsCard { Text(t(.empty)).foregroundStyle(Theme.textSecondary) } }
            ForEach(manager.records) { record in
                SettingsCard {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.package.manifest.name).font(Theme.mono(13, weight: .semibold))
                            Text(record.package.manifest.description).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                            Text(record.package.manifest.version + " · " + record.package.manifest.author + " · " + (record.origin == "local" ? t(.local) : URL(string: record.origin)?.host ?? t(.catalog)))
                                .font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                            Text(status(record)).font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                        }.fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 10)
                        VStack(alignment: .trailing, spacing: 8) {
                            if record.wantedEnabled && manager.active.contains(record.id) {
                                Button(t(.disable)) { manager.disable(record.id) }
                            } else {
                                Button(t(.enable)) { approving = record }.disabled(record.package.compatibilityIssue != nil)
                            }
                            Button(t(.remove)) { manager.remove(record.id) }
                        }
                    }
                    ForEach(record.package.manifest.settings, id: \.key) { descriptor in setting(record, descriptor) }
                }
            }
            ForEach(manager.catalog) { entry in
                SettingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.name).font(Theme.mono(12, weight: .semibold))
                            Text(entry.description).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                            Text(entry.version + " · " + entry.author).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer(minLength: 8)
                        Button(t(.install)) { Task { await manager.installCatalog(entry) } }.disabled(manager.busy)
                    }
                }
            }
            if !manager.active.isEmpty { Button(t(.recovery)) { manager.disableAll() } }
        }
        .font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
        .sheet(item: $approving) { record in
            VStack(alignment: .leading, spacing: 16) {
                Text(record.package.manifest.name).font(Theme.mono(17, weight: .semibold))
                Text(t(.permissions)).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                ForEach(record.package.manifest.capabilities, id: \.self) { Text("• " + PluginCopy.capability($0, lang)).font(Theme.mono(12)) }
                HStack {
                    Button(t(.cancel)) { approving = nil }
                    Spacer()
                    Button(t(.approve)) {
                        manager.approve(record.id, digest: record.digest, capabilities: Set(record.package.manifest.capabilities))
                        approving = nil
                    }.keyboardShortcut(.defaultAction)
                }.padding(.top, 8)
            }.padding(24).frame(width: 430).background(Theme.background).foregroundStyle(Theme.textPrimary)
        }
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
