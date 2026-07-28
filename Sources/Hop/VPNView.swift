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

    /// Same cap-and-scroll as the clipboard and the task lists: past the cap the
    /// rows scroll inside a fixed height, so a long list cannot push the modules
    /// below it off the panel.
    @AppStorage(VPNController.visibleRowsKey) private var visibleRows = VPNController.defaultVisibleRows

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
            } else if !Snapshot.active,
                      let height = RowCap.listHeight(stored: visibleRows,
                                                     count: vpn.configurations.count) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(vpn.configurations) { row($0) }
                    }
                }
                .frame(height: height)
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
            // No indicator light and no gutter where one used to be: the switch
            // on the right already says on or off, and the row starts on the same
            // left line as every other module's text (Anton, 2026-07-29). The
            // menu-bar icon carries the light, for when the panel is closed.
            Button { vpn.openApp(for: configuration) } label: {
                // Baseline alignment, not top: the smaller text sat high and read
                // as a superscript (Anton, 2026-07-29).
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(configuration.title)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.listText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    // what the configuration adds to the app's name — the country
                    // it was set to, or the protocol — in brackets and quieter
                    if let subtitle = configuration.subtitle {
                        Text("(\(subtitle))")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
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

}
