import AppKit
import HopCore
import SwiftUI

/// SPEC: docs/spec.md — "Network access". The module's row in the panel: the
/// name opens the window, the switch turns the filter on and off.
struct NetworkView: View {
    @ObservedObject var network: NetworkFilterController
    let lang: AppLanguage
    var openWindow: () -> Void = {}

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: openWindow) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(t(.networkLabel))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.listText)
                        .lineLimit(1)
                    if let status = NetworkStatusText.line(network, lang) {
                        Text(status.text)
                            .font(Theme.mono(10))
                            .foregroundStyle(status.warning ? Theme.accentOrange : Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverDim()
            .help(t(.networkOpenWindow))
            Spacer(minLength: 6)
            Theme.MiniSwitch(isOn: Binding(
                get: { network.state.wantsOn },
                set: { $0 ? network.switchOn() : network.switchOff() }
            ))
            .help(t(network.state.wantsOn ? .networkSwitchOff : .networkSwitchOn))
        }
        .padding(.vertical, 2)
    }
}

@MainActor
enum NetworkStatusText {
    static func line(_ network: NetworkFilterController, _ lang: AppLanguage) -> (text: String, warning: Bool)? {
        switch network.state {
        case .off: return nil
        case .installing: return (L10n.t(.networkInstalling, lang), false)
        case .needsApproval: return (L10n.t(.networkNeedsApproval, lang), true)
        case .failed: return (L10n.t(.networkFailed, lang), true)
        case .on:
            if network.stopped { return (L10n.t(.networkStopped, lang), true) }
            let blocked = network.rules.filter { $0.action == .deny }.count
            return blocked == 0 ? nil
                : (L10n.t(.networkRulesCount, lang).replacingOccurrences(of: "%d", with: "\(blocked)"), false)
        }
    }
}

extension NetworkFilterController.State {
    var wantsOn: Bool {
        switch self {
        case .on, .installing, .needsApproval: return true
        case .off, .failed: return false
        }
    }
}

/// SPEC: docs/spec.md — "Network access", the window.
struct NetworkWindowView: View {
    @ObservedObject var network: NetworkFilterController
    let lang: AppLanguage
    var preview = false

    enum Filter: CaseIterable { case all, blocked, recent }

    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var expanded: Set<String> = []
    @State private var adding = false
    @State private var newApp = ""
    @State private var newHost = ""
    @State private var newAction: NetworkRule.Action = .deny
    @State private var note: String?

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
    private var staged: Bool { preview || Snapshot.active }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            // SPEC: docs/spec.md — "Network access": nothing to set up until the
            // filter runs, or the switches would look as if they worked.
            if network.state == .on {
                toolbar
                if let note {
                    Text(note)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                content
            } else {
                setup
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 20)
        .frame(minWidth: 560, minHeight: 440, alignment: .top)
        .background(Theme.background)
        .onAppear { if !preview { network.watch() } }
        .onDisappear { if !preview { network.unwatch() } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 18))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 40, height: 40)
                .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(t(.networkLabel))
                    .font(Theme.mono(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(t(.purposeNetwork))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: before the filter runs

    private var setup: some View {
        SettingsCard(spacing: 12) {
            switch network.state {
            case .needsApproval:
                Text(t(.networkSetupTitle))
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                step(1, t(.networkStepOpen))
                step(2, t(.networkStepPath))
                step(3, t(.networkStepAllow))
                primary(t(.networkOpenSettings)) { NetworkFilterController.openSystemSettings() }
                    .padding(.top, 4)
            case .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(t(.networkInstalling))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            case .failed(let reason):
                Text(t(.networkFailed))
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !reason.isEmpty {
                    Text(reason)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                primary(t(.networkSwitchOn)) { network.switchOn() }
            case .off, .on:
                Text(t(.networkOffTitle))
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(t(.networkOffNote))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                primary(t(.networkSwitchOn)) { network.switchOn() }
                    .padding(.top, 4)
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(Theme.mono(10, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 20, height: 20)
                .background(Theme.chipBg, in: Circle())
            Text(text)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.mono(11, weight: .bold))
                .foregroundStyle(Theme.playFg)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
    }

    // MARK: toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                TextField(t(.networkSearch), text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 8))
            segments
            Menu {
                Button(t(.networkImport)) { importRules() }
                Button(t(.networkExport)) { exportRules() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            primary("+ " + t(.networkAddRule)) { adding = true }
                .popover(isPresented: $adding, arrowEdge: .bottom) { addForm }
        }
    }

    private var segments: some View {
        HStack(spacing: 2) {
            ForEach(Filter.allCases, id: \.self) { option in
                let label: L10nKey = switch option {
                case .all: .networkFilterAll
                case .blocked: .networkFilterBlocked
                case .recent: .networkFilterRecent
                }
                Button { filter = option } label: {
                    Text(t(label))
                        .font(Theme.mono(11))
                        .foregroundStyle(filter == option ? Theme.textPrimary : Theme.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(filter == option ? Theme.chipBg : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 8))
        .fixedSize()
    }

    // MARK: a rule made ahead of time

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t(.networkAddTitle))
                .font(Theme.mono(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            labelled(t(.networkRuleProgram)) {
                Menu {
                    Button(t(.networkAnyProgram)) { newApp = NetworkRule.anyProgram }
                    Divider()
                    ForEach(network.programs.filter { $0.app != NetworkRule.anyProgram }, id: \.app) { program in
                        Button(NetworkProgramLook.name(program.app, program.path)) { newApp = program.app }
                    }
                    Divider()
                    ForEach(network.installed, id: \.id) { app in
                        Button(app.name) { newApp = app.id }
                    }
                    Divider()
                    Button(t(.networkChooseApp)) { chooseApp() }
                } label: {
                    Text(newApp.isEmpty ? t(.networkChooseApp) : programName(newApp, nil))
                        .font(Theme.mono(12))
                }
                .menuStyle(.borderlessButton)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 8))
            }
            labelled(t(.networkRuleAddress)) {
                TextField(t(.networkAddressHint), text: $newHost)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 8))
            }
            labelled(t(.networkRuleWhat)) {
                Picker("", selection: $newAction) {
                    Text(t(.networkBlock)).tag(NetworkRule.Action.deny)
                    Text(t(.networkAllow)).tag(NetworkRule.Action.allow)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack {
                Spacer()
                primary(t(.networkAdd)) { addRule() }
                    .disabled(newApp.isEmpty
                              || (newApp == NetworkRule.anyProgram && newHost.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textTertiary)
            content()
        }
    }

    private func addRule() {
        let host = newHost.trimmingCharacters(in: .whitespaces)
        if host.isEmpty {
            network.setProgram(newApp, allowed: newAction == .allow)
        } else {
            network.setDestination(newApp, host, action: newAction)
        }
        expanded.insert(newApp)
        newHost = ""
        adding = false
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        newApp = id
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .json, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let count = network.importRules(from: url), count > 0 else {
            note = t(.networkImportEmpty)
            return
        }
        note = t(.networkImported).replacingOccurrences(of: "%d", with: "\(count)")
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "hop-network-rules.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = network.exportRules(to: url)
    }

    // MARK: the lists

    private func matches(_ app: String, _ path: String?, hosts: [String]) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return programName(app, path).lowercased().contains(needle) || app.lowercased().contains(needle)
            || hosts.contains { $0.lowercased().contains(needle) }
    }

    private var seen: [NetworkProgram] {
        let hourAgo = Date().addingTimeInterval(-3600)
        return network.programs.filter { program in
            guard program.app != NetworkRule.anyProgram else { return false }
            switch filter {
            case .all: break
            case .blocked:
                guard program.blocked || network.rules.contains(where: { $0.app == program.app && $0.action == .deny })
                else { return false }
            case .recent:
                guard let last = program.last, last > hourAgo else { return false }
            }
            return matches(program.app, program.path, hosts: destinations(program))
        }
    }

    private var anyProgram: NetworkProgram? {
        guard filter != .recent,
              let program = network.programs.first(where: { $0.app == NetworkRule.anyProgram }),
              matches(program.app, nil, hosts: destinations(program)) else { return nil }
        return program
    }

    private var others: [(id: String, name: String)] {
        guard filter == .all else { return [] }
        let listed = Set(network.programs.map(\.app))
        return network.installed.filter { !listed.contains($0.id) && matches($0.id, nil, hosts: []) }
    }

    @ViewBuilder private var content: some View {
        let seen = self.seen, any = anyProgram, others = self.others
        if seen.isEmpty && any == nil && others.isEmpty {
            Text(network.programs.isEmpty ? t(.networkEmpty) : t(.networkNothingFound))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        } else if staged {
            // A ScrollView renders empty in a snapshot: renders get the sections bare.
            sections(seen: seen, any: any, others: others)
            Spacer(minLength: 0)
        } else {
            ScrollView { sections(seen: seen, any: any, others: others) }
        }
    }

    private func sections(seen: [NetworkProgram], any: NetworkProgram?,
                          others: [(id: String, name: String)]) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if !seen.isEmpty {
                SettingsGroupLabel(title: t(.networkSectionSeen))
                SettingsCard(spacing: 0) {
                    ForEach(Array(seen.enumerated()), id: \.element.app) { index, program in
                        if index > 0 { SettingsRule().padding(.vertical, 2) }
                        programRow(program)
                    }
                }
            }
            if let any {
                SettingsGroupLabel(title: t(.networkSectionAny)).padding(.top, 10)
                SettingsCard(spacing: 0) {
                    ForEach(Array(destinations(any).enumerated()), id: \.element) { index, host in
                        if index > 0 { SettingsRule().padding(.vertical, 2) }
                        destinationRow(any, host, inset: 0)
                    }
                }
            }
            if !others.isEmpty {
                SettingsGroupLabel(title: t(.networkSectionOthers)).padding(.top, 10)
                SettingsCard(spacing: 0) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, app in
                        if index > 0 { SettingsRule().padding(.vertical, 2) }
                        otherRow(app.id)
                    }
                }
            }
        }
    }

    /// Destinations seen, then those with a rule made ahead of time.
    private func destinations(_ program: NetworkProgram) -> [String] {
        var hosts = program.destinations.map(\.destination)
        for rule in network.rules where rule.app == program.app {
            if let host = rule.host, !hosts.contains(host) { hosts.append(host) }
        }
        return hosts
    }

    private func programName(_ app: String, _ path: String?) -> String {
        app == NetworkRule.anyProgram ? t(.networkAnyProgram) : NetworkProgramLook.name(app, path)
    }

    private func programRow(_ program: NetworkProgram) -> some View {
        let hosts = destinations(program)
        let open = staged || expanded.contains(program.app)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Button {
                    if expanded.contains(program.app) { expanded.remove(program.app) } else { expanded.insert(program.app) }
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NetworkProgramLook.icon(program.app, program.path))
                            .resizable()
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(programName(program.app, program.path))
                                .font(Theme.mono(12, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(summary(program, hosts: hosts.count))
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if !hosts.isEmpty {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                                .rotationEffect(.degrees(open ? 0 : -90))
                        }
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                VerdictPill(allowed: !program.blocked, lang: lang) {
                    network.setProgram(program.app, allowed: program.blocked)
                }
                .help(t(program.blocked ? .networkAllowProgram : .networkBlockProgram))
            }
            if open {
                ForEach(hosts, id: \.self) { host in
                    destinationRow(program, host, inset: 32)
                }
            }
        }
    }

    private func otherRow(_ app: String) -> some View {
        let blocked = network.rules.contains { $0.app == app && $0.host == nil && $0.action == .deny }
        return HStack(spacing: 10) {
            Image(nsImage: NetworkProgramLook.icon(app, nil))
                .resizable()
                .frame(width: 18, height: 18)
            Text(NetworkProgramLook.name(app, nil))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            VerdictPill(allowed: !blocked, lang: lang) { network.setProgram(app, allowed: blocked) }
                .help(t(blocked ? .networkAllowProgram : .networkBlockProgram))
        }
        .padding(.vertical, 5)
    }

    private func summary(_ program: NetworkProgram, hosts: Int) -> String {
        var parts = [L10n.t(.networkAddressesCount, lang).replacingOccurrences(of: "%d", with: "\(hosts)")]
        if let last = program.last {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: lang.rawValue)
            formatter.unitsStyle = .full
            parts.append(formatter.localizedString(for: last, relativeTo: Date()))
        }
        return parts.joined(separator: " · ")
    }

    private func destinationRow(_ program: NetworkProgram, _ host: String, inset: CGFloat) -> some View {
        let own = network.rules.first { $0.app == program.app && $0.host == host }
        let allowed = network.verdict(program.app, host) == .allow
        let seen = program.destinations.first { $0.destination == host }
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(host)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.listText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let seen {
                    Text(":\(seen.port) · ×\(seen.count)")
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 6)
            if own != nil && program.app != NetworkRule.anyProgram {
                Button { network.setDestination(program.app, host, action: nil) } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .hoverDim()
                .help(t(.networkFollowProgram))
            }
            if program.app == NetworkRule.anyProgram {
                Button { network.setDestination(program.app, host, action: nil) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .hoverDim()
            }
            VerdictPill(allowed: allowed, lang: lang, small: true) {
                network.setDestination(program.app, host, action: allowed ? .deny : .allow)
            }
            .help(t(allowed ? .networkBlockAddress : .networkAllowAddress))
        }
        .padding(.leading, inset)
        .padding(.vertical, 4)
    }
}

/// "allowed" in green or "blocked" in red: a switch alone did not say which
/// way it was set. A click turns it over.
struct VerdictPill: View {
    let allowed: Bool
    let lang: AppLanguage
    var small = false
    let action: () -> Void

    var body: some View {
        let tint = allowed ? Theme.accentGreen : Theme.accentRed
        Button(action: action) {
            Text(L10n.t(allowed ? .networkAllowed : .networkBlocked, lang))
                .font(Theme.mono(small ? 9.5 : 10.5, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, small ? 8 : 10)
                .padding(.vertical, small ? 3 : 5)
                .background(tint.opacity(0.14), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverDim()
    }
}

/// A program's name and icon from its signing identifier and executable path.
@MainActor
enum NetworkProgramLook {
    private static var cache: [String: (name: String, icon: NSImage)] = [:]

    static func name(_ app: String, _ path: String?) -> String { look(app, path).name }
    static func icon(_ app: String, _ path: String?) -> NSImage { look(app, path).icon }

    /// A plain bitmap: the system's layered icon renders as a grey veil over the
    /// whole snapshot, and a flat picture is cheaper to redraw in a long list.
    private static func flattened(_ icon: NSImage) -> NSImage {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 72, pixelsHigh: 72, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return icon }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: 72, height: 72))
        NSGraphicsContext.restoreGraphicsState()
        let flat = NSImage(size: NSSize(width: 36, height: 36))
        flat.addRepresentation(rep)
        return flat
    }

    private static func look(_ app: String, _ path: String?) -> (name: String, icon: NSImage) {
        if let known = cache[app] { return known }
        var bundlePath: String?
        if let path, let range = path.range(of: ".app/", options: .backwards) {
            bundlePath = String(path[..<range.lowerBound]) + ".app"
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
            bundlePath = url.path
        }
        let result: (String, NSImage)
        if let bundlePath {
            let name = FileManager.default.displayName(atPath: bundlePath)
                .replacingOccurrences(of: ".app", with: "")
            result = (name, NSWorkspace.shared.icon(forFile: bundlePath))
        } else {
            let name = path.map { ($0 as NSString).lastPathComponent } ?? app
            result = (name, NSWorkspace.shared.icon(for: .unixExecutable))
        }
        let flat = (result.0, flattened(result.1))
        cache[app] = flat
        return flat
    }
}

