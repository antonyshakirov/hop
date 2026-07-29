import SwiftUI

/// First-launch window: language, theme, launch at login — then off to the bar.
struct OnboardingView: View {
    let updater: UpdateChecker
    /// The app's own shelves store, so a grid chosen here is the same grid the
    /// panel shows a moment later.
    @ObservedObject var shelves: AppShelvesController
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
    // The module choices are transient @State, not @AppStorage: visibility is
    // membership now, so onboarding drives the panel-tabs model directly (see
    // finishOnboarding) instead of the dead show*Module keys. displayStyle is a
    // real persisted setting and stays @AppStorage.
    @State private var showTimerModule = true
    @AppStorage("displayStyle") private var displayStyle = "dots"
    @State private var showAwakeModule = true
    @State private var showClipboardModule = true
    @State private var showConvertModule = true
    @State private var showWindowsModule = true
    @State private var showSystemModule = true
    @State private var showTrackerModule = true
    @State private var showTodosModule = true
    // Torrents default OFF globally (opt-in via the "what's new" banner for users
    // who updated in); a fresh install gets to choose here, recommended on.
    @State private var enableTorrent = true
    // The 1.5.0 modules belong on this screen too — a fresh install should see
    // EVERYTHING it can have and decide once (Anton, 2026-07-26). Archives and
    // the keyboard lock are everyday tools, so they start on; the eyedropper and
    // recognition serve designers and developers, so they start off.
    @State private var showArchiveModule = true
    @State private var showKeyboardModule = true
    @State private var showColorModule = true
    @State private var showOcrModule = true
    /// VPN ships off for the same reason: a Mac with no VPN configured would get
    /// an empty section it never asked for.
    @State private var showVpnModule = true
    /// On like the rest (Anton, 2026-07-29): saying yes creates one empty grid,
    /// which explains itself in the panel rather than staying invisible.
    @State private var showAppsModule = true

    /// One module in the grid: name on the left, switch on the right — the same
    /// shape as the rows above it, three to a line in a window widened to fit
    /// them (Anton, 2026-07-29). The earlier switch-above-name cell only existed
    /// because the window was panel-narrow.
    private func moduleCell(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Theme.MiniSwitch(isOn: isOn)
        }
        .frame(maxWidth: .infinity)
    }

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
                HStack {
                    Text(t(.launchAtLogin))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Theme.MiniSwitch(isOn: $launchAtLogin)
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

                // Every module switch lives here. TWO columns with a wide gutter,
                // not three: at three the gap between a switch and the next
                // column's name was smaller than the gap to its own name, so the
                // switch read as belonging to the wrong row (Anton, 2026-07-29).
                // Top-aligned: a two-line name must not lift its switch above
                // its neighbour's.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 34, alignment: .top),
                                         count: 2),
                          spacing: 12) {
                    moduleCell(t(.aboutTabTimer), isOn: $showTimerModule)
                    moduleCell(t(.awakeOff), isOn: $showAwakeModule)
                    moduleCell(t(.tabClipboard), isOn: $showClipboardModule)
                    moduleCell(t(.convertLabel), isOn: $showConvertModule)
                    moduleCell(t(.windowsLabel), isOn: $showWindowsModule)
                    moduleCell(t(.tabSystem), isOn: $showSystemModule)
                    moduleCell(t(.trackerLabel), isOn: $showTrackerModule)
                    moduleCell(t(.todosLabel), isOn: $showTodosModule)
                    moduleCell(t(.archiveLabel), isOn: $showArchiveModule)
                    moduleCell(t(.keylockLabel), isOn: $showKeyboardModule)
                    moduleCell(t(.torrentLabel), isOn: $enableTorrent)
                    moduleCell(t(.colorLabel), isOn: $showColorModule)
                    moduleCell(t(.ocrLabel), isOn: $showOcrModule)
                    moduleCell(t(.vpnLabel), isOn: $showVpnModule)
                    moduleCell(t(.appsLabel), isOn: $showAppsModule)
                }
                // The one module with a real extra cost: a one-time separate
                // engine download — say so before the choice, not after. It
                // names torrents now, since the note no longer sits beside them.
                Text("\(t(.torrentLabel)): \(t(.torrentEngineNote))")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text(L10n.fill(.updateAvailable, lang, info.version))
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
        // Wide enough for three name+switch columns; the module choices are the
        // widest thing in the window and everything else just centres in it.
        .frame(width: 560)
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
        // Fresh install: apply the module choices to the spaces directly.
        // Visibility is membership now — a chosen module stays on its canonical
        // space, an unchosen one goes to the inactive bucket (the loadTabs
        // migration ran with defaults before onboarding, so reconcile
        // explicitly here). The fresh migrate already put every module on its
        // canonical space (general on space 1, system on space 2, tracker+todos
        // on space 3), so an "on" choice is a no-op and only "off" moves a
        // module out — except torrent, which starts inactive and activates onto
        // space 1.
        let choices: [(module: String, on: Bool)] = [
            ("timer", showTimerModule), ("awake", showAwakeModule),
            ("clipboard", showClipboardModule), ("convert", showConvertModule),
            ("windows", showWindowsModule), ("torrent", enableTorrent),
            ("system", showSystemModule), ("tracker", showTrackerModule),
            ("todos", showTodosModule), ("archive", showArchiveModule),
            ("keyboard", showKeyboardModule), ("color", showColorModule),
            ("vpn", showVpnModule),
            ("ocr", showOcrModule),
        ]
        for choice in choices {
            if choice.on { PanelView.activateStoredModule(choice.module) }
            else { PanelView.deactivateStoredModule(choice.module) }
        }
        // Apps is the one choice that has nothing to switch on: the module only
        // exists once a grid does, so saying yes here makes the first one.
        if showAppsModule {
            PanelView.activateStoredModule(shelves.addShelf())
        }
        // Deactivating the monitor / tracker / to-dos can empty their canonical
        // spaces (space 2, space 3); drop any that ended up empty so the app
        // never opens onto a blank tab.
        PanelView.dropEmptyOnboardingSpaces()
        // Mark EVERY "what's new" announcement as seen — the top-of-panel banner
        // exists for people who updated INTO a feature, and this user has just
        // been asked about all of them by name. Listing the ids by hand meant a
        // new announcement started greeting fresh installs with a question they
        // had already answered (Anton, 2026-07-29).
        for id in PanelView.featureAnnouncementIDs {
            UserDefaults.standard.set(true, forKey: "featureSeen.\(id)")
        }
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
