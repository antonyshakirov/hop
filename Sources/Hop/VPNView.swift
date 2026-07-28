import HopCore
import SwiftUI

/// The VPN module: one row per configuration macOS knows about — a light, the
/// name, and a switch. Nothing to add by hand; anything that registers itself in
/// network settings appears here on its own.
///
/// The name is a button: it brings up the vendor's own window for the times you
/// need it (pick a country, change a setting), and Hop quits that app again once
/// the window is closed, so it never sits in the Dock for a switch you touch
/// twice a week.
struct VPNView: View {
    @ObservedObject var vpn: VPNController
    let lang: AppLanguage

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            subheader
            if vpn.configurations.isEmpty {
                Text(t(.vpnEmpty))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
            } else {
                ForEach(vpn.configurations) { row($0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { vpn.startPolling() }
        .onDisappear { vpn.stopPolling() }
    }

    /// Same treatment as the tracker and to-do sublabels, so a stack of modules
    /// on one space reads as a list of sections.
    private var subheader: some View {
        Text(t(.vpnLabel))
            .font(Theme.mono(10, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 2)
    }

    private func row(_ configuration: VPNConfiguration) -> some View {
        let busy = configuration.state.isBusy || vpn.pending.contains(configuration.id)
        return HStack(spacing: 6) {
            light(on: configuration.state.isOn, busy: busy)
            Button { vpn.openApp(for: configuration) } label: {
                Text(configuration.name)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.listText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverDim()
            .disabled(configuration.bundleIdentifier == nil)
            .help(t(.vpnOpenApp))
            Spacer(minLength: 6)
            Theme.MiniSwitch(isOn: Binding(
                get: { configuration.state.isOn },
                set: { _ in vpn.toggle(configuration) }
            ), tint: Theme.accentGreen)
            .opacity(busy ? 0.5 : 1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    /// Green while the tunnel is up, hollow while it is not, dimmed mid-flight.
    /// Left-aligned in the same 22pt gutter as the tracker's play button and the
    /// to-do checkbox, so the modules line up on one left column.
    private func light(on: Bool, busy: Bool) -> some View {
        Circle()
            .fill(on ? Theme.accentGreen : .clear)
            .overlay(
                Circle().strokeBorder(on ? .clear : Theme.textTertiary, lineWidth: 1.5)
            )
            .frame(width: 10, height: 10)
            .opacity(busy ? 0.45 : 1)
            .frame(width: RowCircle.gutter, alignment: .leading)
    }
}
