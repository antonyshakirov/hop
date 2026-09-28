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

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if network.state != .on { stateCard }
            controls
            if adding { addForm }
            list
        }
        .padding(22)
        .padding(.top, 18)
        .frame(minWidth: 520, minHeight: 420, alignment: .top)
        .background(Theme.background)
        .onAppear { if !preview { network.watch() } }
        .onDisappear { if !preview { network.unwatch() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t(.networkLabel))
                .font(Theme.mono(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(t(.purposeNetwork))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var stateCard: some View {
        HStack(spacing: 10) {
            Text(stateText)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            switch network.state {
            case .needsApproval:
                actionButton(t(.networkOpenSettings)) { NetworkFilterController.openSystemSettings() }
            case .off, .failed:
                actionButton(t(.networkSwitchOn)) { network.switchOn() }
            default:
                EmptyView()
            }
        }
        .padding(12)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 9))
    }

    private var stateText: String {
        switch network.state {
        case .off: return t(.networkOffNote)
        case .installing: return t(.networkInstalling)
        case .needsApproval: return t(.networkApprovalNote)
        case .failed(let reason): return t(.networkFailed) + (reason.isEmpty ? "" : ": " + reason)
        case .on: return ""
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                TextField(t(.networkSearch), text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 7))
            ForEach(Filter.allCases, id: \.self) { option in
                chip(option)
            }
            actionButton("+ " + t(.networkAddRule)) { adding.toggle() }
        }
    }

    private func chip(_ option: Filter) -> some View {
        let label: L10nKey = switch option {
        case .all: .networkFilterAll
        case .blocked: .networkFilterBlocked
        case .recent: .networkFilterRecent
        }
        return Button { filter = option } label: {
            Text(t(label))
                .font(Theme.mono(11))
                .foregroundStyle(filter == option ? Theme.textPrimary : Theme.textTertiary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(filter == option ? Theme.chipBg : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
    }

    // MARK: adding a rule ahead of time

    private var addForm: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(network.programs, id: \.app) { program in
                    Button(NetworkProgramLook.name(program.app, program.path)) { newApp = program.app }
                }
                Divider()
                Button(t(.networkChooseApp)) { chooseApp() }
            } label: {
                Text(newApp.isEmpty ? t(.networkRuleProgram) : NetworkProgramLook.name(newApp, nil))
                    .font(Theme.mono(11))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            TextField(t(.networkRuleAddress), text: $newHost)
                .textFieldStyle(.plain)
                .font(Theme.mono(12))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 7))
            Picker("", selection: $newAction) {
                Text(t(.networkBlock)).tag(NetworkRule.Action.deny)
                Text(t(.networkAllow)).tag(NetworkRule.Action.allow)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            actionButton(t(.networkAdd)) {
                guard !newApp.isEmpty else { return }
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
            .disabled(newApp.isEmpty)
        }
        .padding(10)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 9))
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        newApp = id
    }

    // MARK: the list

    private var visible: [NetworkProgram] {
        let hourAgo = Date().addingTimeInterval(-3600)
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return network.programs.filter { program in
            switch filter {
            case .all: break
            case .blocked:
                guard program.blocked || network.rules.contains(where: { $0.app == program.app && $0.action == .deny })
                else { return false }
            case .recent:
                guard let last = program.last, last > hourAgo else { return false }
            }
            guard !needle.isEmpty else { return true }
            return NetworkProgramLook.name(program.app, program.path).lowercased().contains(needle)
                || program.app.lowercased().contains(needle)
                || destinations(program).contains { $0.lowercased().contains(needle) }
        }
    }

    @ViewBuilder private var list: some View {
        let programs = visible
        if programs.isEmpty {
            Text(network.programs.isEmpty ? t(.networkEmpty) : t(.networkNothingFound))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 6)
            Spacer(minLength: 0)
        } else if preview || Snapshot.active {
            // A ScrollView renders empty in a snapshot, so renders get the rows
            // bare, with every program open.
            VStack(alignment: .leading, spacing: 4) { rows(programs, openAll: true) }
            Spacer(minLength: 0)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) { rows(programs, openAll: false) }
            }
        }
    }

    @ViewBuilder private func rows(_ programs: [NetworkProgram], openAll: Bool) -> some View {
        ForEach(programs, id: \.app) { program in
            programRow(program, open: openAll || expanded.contains(program.app))
            if openAll || expanded.contains(program.app) {
                ForEach(destinations(program), id: \.self) { host in
                    destinationRow(program, host)
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

    private func programRow(_ program: NetworkProgram, open: Bool) -> some View {
        return HStack(spacing: 8) {
            Button {
                if open { expanded.remove(program.app) } else { expanded.insert(program.app) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 10)
                    Image(nsImage: NetworkProgramLook.icon(program.app, program.path))
                        .resizable()
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(NetworkProgramLook.name(program.app, program.path))
                            .font(Theme.mono(12))
                            .foregroundStyle(program.blocked ? Theme.textTertiary : Theme.textPrimary)
                            .lineLimit(1)
                        Text(summary(program))
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Theme.MiniSwitch(isOn: Binding(
                get: { !program.blocked },
                set: { network.setProgram(program.app, allowed: $0) }
            ))
            .help(t(program.blocked ? .networkAllowProgram : .networkBlockProgram))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 8))
    }

    private func summary(_ program: NetworkProgram) -> String {
        var parts = [L10n.t(.networkAddressesCount, lang)
            .replacingOccurrences(of: "%d", with: "\(destinations(program).count)")]
        if let last = program.last {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: lang.rawValue)
            formatter.unitsStyle = .short
            parts.append(formatter.localizedString(for: last, relativeTo: Date()))
        }
        return parts.joined(separator: " · ")
    }

    private func destinationRow(_ program: NetworkProgram, _ host: String) -> some View {
        let own = network.rules.first { $0.app == program.app && $0.host == host }
        let allowed = network.verdict(program.app, host) == .allow
        let seen = program.destinations.first { $0.destination == host }
        return HStack(spacing: 8) {
            Text(host)
                .font(Theme.mono(11))
                .foregroundStyle(allowed ? Theme.listText : Theme.textTertiary)
                .strikethrough(!allowed, color: Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if let seen {
                Text(":\(seen.port) · ×\(seen.count)")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 6)
            if own != nil {
                Button { network.setDestination(program.app, host, action: nil) } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .hoverDim()
                .help(t(.networkFollowProgram))
            }
            Theme.MiniSwitch(isOn: Binding(
                get: { allowed },
                set: { network.setDestination(program.app, host, action: $0 ? .allow : .deny) }
            ))
            .help(t(allowed ? .networkBlockAddress : .networkAllowAddress))
        }
        .padding(.leading, 46)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
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

