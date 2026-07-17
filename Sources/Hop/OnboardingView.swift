import SwiftUI

/// First-launch window: language, theme, launch at login — then off to the bar.
struct OnboardingView: View {
    let updater: UpdateChecker
    let finish: () -> Void

    private enum Phase {
        case form
        case checking
        case offer(UpdateChecker.ReleaseInfo)
    }
    @State private var phase: Phase = .form

    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"
    @AppStorage(Theme.themeKey) private var themeRaw = "auto"
    @State private var launchAtLogin = true
    @State private var menuTarget: MenuPickTarget?
    @AppStorage("showTimerModule") private var showTimerModule = true
    @AppStorage("displayStyle") private var displayStyle = "dots"
    @AppStorage("showAwakeModule") private var showAwakeModule = true
    @AppStorage("showClipboardModule") private var showClipboardModule = true
    @AppStorage("showConvertModule") private var showConvertModule = true
    @AppStorage("showWindowsModule") private var showWindowsModule = true
    // Torrents default OFF globally (opt-in via the "what's new" banner for users
    // who updated in); a fresh install gets to choose here, recommended on.
    @State private var enableTorrent = true

    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 9) {
                asterisk // vector: the menu bar bitmap got blurry when scaled up
                Text("hop")
                    .font(Theme.mono(17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.top, 2)

            VStack(spacing: 14) {
                HStack {
                    Text(t(.language))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    languagePicker
                }
                HStack {
                    Text(t(.themeLabel))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    chip("auto", t(.themeAuto))
                    chip("dark", t(.themeDark))
                    chip("light", t(.themeLight))
                }
                VStack(spacing: 6) {
                    HStack {
                        Text(t(.displayStyleLabel))
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                    // digits of all three previews share one visual height,
                    // as in settings (the window is narrower, so slightly smaller)
                    HStack(spacing: 6) {
                        displayCard("dots", DotMatrixDisplay(text: "12:34", dimCount: 0, blinkOff: false, cell: 1.8))
                        displayCard("text", Text("12:34").font(Theme.mono(15, weight: .semibold)).monospacedDigit())
                        displayCard("units", Text("12\(t(.unitMin)) 34\(t(.unitSec))").font(Theme.mono(15, weight: .semibold)).monospacedDigit())
                    }
                    // dots take their color from Theme at draw time — on a live
                    // theme change we recreate the row, otherwise dark dots on dark
                    .id("displayPreview-\(themeRaw)")
                }

                HStack {
                    Text(t(.launchAtLogin))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Theme.MiniSwitch(isOn: $launchAtLogin)
                }
                HStack {
                    Text(t(.showTimerLabel))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Theme.MiniSwitch(isOn: $showTimerModule)
                }
                HStack {
                    Text(t(.showAwakeLabel))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Theme.MiniSwitch(isOn: $showAwakeModule)
                }
                HStack {
                    Text(t(.showClipboardLabel))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Theme.MiniSwitch(isOn: $showClipboardModule)
                }
                HStack {
                    Text(t(.showConvertLabel))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Theme.MiniSwitch(isOn: $showConvertModule)
                }
                HStack {
                    Text(t(.showWindowsLabel))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Theme.MiniSwitch(isOn: $showWindowsModule)
                }
                HStack {
                    Text(t(.showTorrentLabel))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Theme.MiniSwitch(isOn: $enableTorrent)
                }
            }
            .padding(.vertical, 6)

            switch phase {
            case .form:
                Button {
                    finishOnboarding()
                } label: {
                    Text(t(.onboardStart))
                        .font(Theme.mono(13, weight: .bold))
                        .foregroundStyle(Theme.playFg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
            case .checking:
                Text("…")
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 10)
            case .offer(let info):
                // the archive could be outdated — ask insistently once
                VStack(spacing: 10) {
                    Text(t(.updateAvailable).replacingOccurrences(of: "%@", with: info.version))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Button {
                        Task { await updater.install(info) } // restarts on its own
                    } label: {
                        Text(t(.updateNow))
                            .font(Theme.mono(13, weight: .bold))
                            .foregroundStyle(Theme.playFg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverDim()
                    Button {
                        finish()
                    } label: {
                        Text(t(.updateLater))
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.textSecondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverDim()
                }
            }
        }
        .padding(24)
        .frame(width: 300)
        .background(Theme.panelBackground)
    }

    /// Color taken directly from the theme picked in the form — the global
    /// Theme.isDark lagged behind here during a live switch.
    private var asteriskColor: Color {
        switch themeRaw {
        case "dark": return .white
        case "light": return Color(white: 0.05)
        default: return Theme.systemDark ? .white : Color(white: 0.05)
        }
    }

    private var asterisk: some View {
        // geometry 1:1 with the menu bar icon: 8 rays offset by half a step
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width * 0.38
            for ray in 0..<8 {
                let angle = CGFloat(ray) * .pi / 4 + .pi / 8
                var path = Path()
                path.move(to: center)
                path.addLine(to: CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                ))
                ctx.stroke(path, with: .color(asteriskColor),
                           style: StrokeStyle(lineWidth: size.width * 0.095, lineCap: .round))
            }
        }
        .frame(width: 40, height: 40)
        // SwiftUI does not redraw a Canvas with no input dependencies on a
        // theme change — the id forces it to be recreated with the new color
        .id(themeRaw)
    }

    private var languagePicker: some View {
        LanguagePicker(selection: $languageRaw)
    }

    private func displayCard(_ raw: String, _ preview: some View) -> some View {
        SettingChip(active: displayStyle == raw, action: { displayStyle = raw }) {
            preview
                .frame(height: 20)
                .frame(maxWidth: .infinity)
        }
    }

    private func chip(_ raw: String, _ label: String) -> some View {
        SettingChip(label, active: themeRaw == raw) { themeRaw = raw }
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        // Fresh install: apply the module choices made above and mark the newest
        // features' "what's new" announcements as seen — the top-of-panel banner is
        // only for users who UPDATED from a build that lacked the feature.
        UserDefaults.standard.set(enableTorrent, forKey: "showTorrentModule")
        UserDefaults.standard.set(true, forKey: "featureSeen.torrent")
        if launchAtLogin {
            try? SMAppServiceHelper.enableLaunchAtLogin()
        }
        phase = .checking
        Task {
            if let info = await updater.newerReleaseIfAny() {
                phase = .offer(info)
            } else {
                finish()
            }
        }
    }
}

import ServiceManagement

enum SMAppServiceHelper {
    static func enableLaunchAtLogin() throws {
        guard Bundle.main.bundleIdentifier != nil else { return }
        if SMAppService.mainApp.status != .enabled {
            try SMAppService.mainApp.register()
        }
    }
}
