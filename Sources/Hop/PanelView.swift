import Carbon.HIToolbox
import CoreServices
import ServiceManagement
import SwiftUI
import HopCore

struct PanelView: View {
    /// A panel screen: one of the user's spaces, or an overlay (settings/about).
    enum Screen: Equatable {
        case space(UUID)
        case settings
        case about
    }

    /// What to show when the panel is (re)built. Resolved against the stored
    /// tabs into a concrete `Screen`: `.restore` is the normal open (last
    /// active space); the rest drive snapshots and status-item targets.
    enum InitialScreen {
        case restore
        case firstSpace
        case spaceContaining(String)
        case settings
        case about
    }

    @EnvironmentObject private var model: AppModel
    @AppStorage(SettingsKey.showMenuBarCountdown) private var showCountdown = true
    @AppStorage(SettingsKey.trackerTimeInBar) private var trackerTimeInBar = false
    @AppStorage(SettingsKey.alertMode) private var alertModeRaw = AlertMode.soundAndBanner.rawValue
    @AppStorage(MediaPauser.settingKey) private var pauseMedia = false
    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"

    @AppStorage(Thresholds.tempYellowKey) private var tempYellow = Thresholds.tempYellowDefault
    @AppStorage(Thresholds.tempRedKey) private var tempRed = Thresholds.tempRedDefault
    @AppStorage(Thresholds.loadYellowKey) private var loadYellow = Thresholds.loadYellowDefault
    @AppStorage(Thresholds.loadRedKey) private var loadRed = Thresholds.loadRedDefault
    @AppStorage(Thresholds.diskYellowKey) private var diskYellow = Thresholds.diskYellowDefault
    @AppStorage(Thresholds.diskRedKey) private var diskRed = Thresholds.diskRedDefault
    @AppStorage(Thresholds.battYellowKey) private var battYellow = Thresholds.battYellowDefault
    @AppStorage(Thresholds.battRedKey) private var battRed = Thresholds.battRedDefault

    @AppStorage(ClipboardController.maxItemsKey) private var clipboardMax = ClipboardController.defaultMaxItems
    @AppStorage(ClipboardController.visibleRowsKey) private var clipboardVisibleRows = ClipboardController.defaultVisibleRows
    @AppStorage("timerCompact") private var timerCompact = true
    @AppStorage("displayStyle") private var displayStyle = "dots" // dots | text | units
    @AppStorage("digitsSize") private var digitsSize = "large" // large | small
    @AppStorage("tempUnit") private var tempUnitRaw = "auto"
    @AppStorage("monitorDetailed") private var monitorDetailed = false
    @AppStorage("monitorWindowMin") private var monitorWindowMin = 5
    @AppStorage(HotkeyManager.snapHotkeysKey) private var windowsHotkeysOn = true
    @AppStorage(SettingsKey.menuBarRedAlert) private var menuBarRedAlert = false
    @AppStorage(Theme.themeKey) private var themeRaw = "auto"
    @AppStorage(AppIcon.styleKey) private var appIconStyle = "auto"
    // Default ON — registered as a UserDefaults default in applicationDidFinishLaunching,
    // which wins over this literal; kept in sync here so the two don't read as contradictory.
    @AppStorage(KeepAwakeController.keepDisplayKey) private var awakeKeepDisplay = true

    @State private var screen: Screen
    // nil → the overlay back button falls through to the restored space
    @State private var overlayReturnScreen: Screen? = nil
    @State private var scrubBaseDuration: TimeInterval?
    @State private var scrubUnit: TimeInterval?
    @State private var launchAtLogin = false
    // "--news" opens the what's-new section directly in a `--window-about`
    // snapshot, so the release-notes design can be reviewed as a picture.
    @State private var aboutSection =
        Snapshot.active && CommandLine.arguments.contains("--news") ? "news" : "general"
    @State private var settingsSection = "general"
    @State private var editUnit: TimeInterval? // digit group being edited (3600/60/1)
    @State private var languageMenuTarget: MenuPickTarget?
    // custom module reorder: the system List.onMove drop indicator
    // (line + leading dot) can't be styled, so rows are dragged by hand
    @State private var dragModuleKey: String?
    @State private var dragModuleOffset: CGFloat = 0
    @State private var dragModuleTarget: Int?
    // header tab reorder (horizontal), mirroring the module row drag
    @State private var dragTabID: UUID?
    @State private var dragTabOffset: CGFloat = 0
    @State private var dragTabTarget: Int?
    // non-nil while the icon picker overlay is up for that tab
    @State private var iconPickerTabID: UUID?
    @AppStorage("cycleTemplates") private var cycleTemplatesRaw = "25/5x4,52/17x3,90/15x2"
    @AppStorage("showPresetsRow") private var showPresetsRow = true
    @AppStorage("showCyclesRow") private var showCyclesRow = true
    @AppStorage("showTimerModule") private var showTimerModule = true
    @AppStorage("showAwakeModule") private var showAwakeModule = true
    @AppStorage("showClipboardModule") private var showClipboardModule = true
    @AppStorage("showConvertModule") private var showConvertModule = true
    @AppStorage(FileConverter.formatKey) private var convFormat = "jpeg"
    @AppStorage(FileConverter.scaleKey) private var convScale = 1.0
    @AppStorage(FileConverter.qualityKey) private var convQuality = 55
    @AppStorage(FileConverter.destKey) private var convDest = "downloads"
    @AppStorage(FileConverter.destPathKey) private var convDestPath = ""
    @AppStorage(FileConverter.autoClearKey) private var convAutoClear = true
    @AppStorage("showWindowsModule") private var showWindowsModule = true
    @AppStorage("showSpeedtestModule") private var showSpeedtestModule = true
    // The system monitor is a module inside its own tab now, toggled like the rest.
    @AppStorage("showSystemModule") private var showSystemModule = true
    // The tracker ships visible by default (not opt-in like torrents): a plain
    // UI module with no engine to download.
    @AppStorage("showTrackerModule") private var showTrackerModule = true
    // Default OFF: a brand-new feature stays hidden until the user opts in via the
    // "what's new" banner (updated users) or onboarding (fresh installs enable it).
    @AppStorage("showTorrentModule") private var showTorrentModule = false
    @AppStorage(TorrentController.downloadDirKey) private var torrentDownloadDir = ""
    @AppStorage(TorrentController.stopAtRatio1Key) private var torrentStopAtRatio1 = false
    @AppStorage(TorrentController.rateDownKey) private var torrentRateDown = 0
    @AppStorage(TorrentController.rateUpKey) private var torrentRateUp = 0
    @AppStorage(TorrentController.showWhenEmptyKey) private var torrentShowWhenEmpty = true
    /// "What's new" banner: dismissed once the user saves their choice.
    @AppStorage("featureSeen.torrent") private var torrentFeatureSeen = false
    // Two-step "what's new" card: step 1 = opt-in (enable/hide), step 2 = the
    // follow-up toggles while the engine fetches in the background.
    // "--feature-banner-step2" renders step 2 directly for design review.
    @State private var bannerEnabled =
        Snapshot.active && CommandLine.arguments.contains("--feature-banner-step2")
    @State private var bannerMakeDefault = false   // step-2 toggle: make Hop default handler
    // speedtest was never in this default string either — it appends
    // via allModules; torrent stays last (opt-in), same mechanism, listed here
    // for an explicit new-user order.
    @AppStorage("moduleOrder") private var moduleOrderRaw = PanelView.defaultModuleOrder
    @AppStorage(SettingsKey.panelTabs) private var panelTabsRaw = ""
    // Last space the user viewed; restored on the next open (mirrors initialTab).
    @AppStorage("activeSpaceID") private var activeSpaceRaw = ""
    @AppStorage("windowsLayout") private var windowsLayout = "grid" // grid | row

    @AppStorage("monitorColorful") private var monitorColorful = false
    @State private var dropTargeted = false
    /// Pause ring flash: click on the locked button while a countdown is running.
    @State private var stopHintPulse = false
    // actual width of the time display: scrub and digit-group click zones
    // derive from it, not from the dot font — scrubbing is uniform across styles
    @State private var displayMeasuredWidth: CGFloat = 0
    // actual panel content height — for clamping to the screen
    @State private var panelContentHeight: CGFloat = 0
    @State private var newCycleWork = 25
    @State private var newCycleRest = 5
    @State private var newCycleRounds = 4
    @State private var lastDisplayTap = Date.distantPast
    @State private var chosenPreset: Int?
    @State private var recordingHotkey: HotkeyManager.Action?
    @State private var hotkeyMonitor: Any?
    @ObservedObject private var hotkeys = HotkeyManager.shared
    @AppStorage(Sounds.enabledKey) private var appSoundsOn = true


    // defaults: breaks/pomodoro/academic hour/hour/ultradian cycle
    static let defaultPresets = "5,15,25,45,60,90"
    @AppStorage("timerPresets") private var presetsRaw = PanelView.defaultPresets
    @AppStorage(UpdateChecker.autoUpdateKey) private var autoUpdateOn = true
    @State private var newPresetMinutes = 20

    private var presets: [Int] {
        let parsed = presetsRaw.split(separator: ",").compactMap { Int($0) }
            .filter { (1...999).contains($0) }
        return parsed.isEmpty
            ? Self.defaultPresets.split(separator: ",").compactMap { Int($0) }
            : Array(Set(parsed)).sorted()
    }

    /// true — standalone settings window (no panel header, wider).
    var standaloneSettings = false
    var standaloneAbout = false

    init(initial: InitialScreen = .restore, standaloneSettings: Bool = false, standaloneAbout: Bool = false) {
        // The panel content view is built once at launch, so this resolves the
        // restored space from UserDefaults directly — as `initialTab` did.
        _screen = State(initialValue: Self.resolve(initial))
        self.standaloneSettings = standaloneSettings
        self.standaloneAbout = standaloneAbout
    }

    private var cycleTemplates: [(work: Int, rest: Int, rounds: Int)] {
        cycleTemplatesRaw.split(separator: ",").compactMap { chunk in
            let parts = chunk.split(whereSeparator: { $0 == "/" || $0 == "x" })
            guard parts.count == 3,
                  let w = Int(parts[0]), let r = Int(parts[1]), let n = Int(parts[2])
            else { return nil }
            return (w, r, n)
        }
    }

    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    /// Product landing in the app's language when it exists (8 languages),
    /// English for everyone else.
    private var productPageURL: String {
        let landing: Set<String> = ["ru", "de", "es", "pt", "fr", "zh", "ja"]
        return landing.contains(lang.rawValue)
            ? "https://antonshakirov.com/products/hop/\(lang.rawValue)"
            : "https://antonshakirov.com/products/hop"
    }

    var body: some View {
        if standaloneSettings {
            if Snapshot.active {
                // ImageRenderer does not render ScrollView content — snapshots
                // take the flat stack at its natural height
                settingsScreen
                    .padding(20)
                    .frame(width: 640)
                    .background(Theme.panelBackground)
            } else {
                ScrollView(showsIndicators: false) {
                    settingsScreen
                        .padding(20)
                        // a theme change must rebuild ALL child views:
                        // LanguagePicker and others get unchanged inputs, so SwiftUI
                        // skips them — text stayed white in the light theme
                        .id(model.themeVersion)
                }
                .frame(width: 640)
                .frame(maxHeight: .infinity)
                .background(Theme.panelBackground)
            }
        } else if standaloneAbout {
            ScrollView(showsIndicators: false) {
                aboutScreen
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // same as settings: a theme change must rebuild children
                    // whose inputs didn't change — the help text kept the old
                    // theme's colors until a tab switch recreated it
                    .id(model.themeVersion)
                    // the window is sized to the active tab's content:
                    // measure and report outward (AppDelegate does the resize,
                    // NOT during the layout pass)
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear { reportAboutHeight(geo.size.height) }
                            .onChange(of: geo.size.height) { _, h in reportAboutHeight(h) }
                    })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.panelBackground)
        } else {
            panelBody
        }
    }

    /// Invariant #1: the panel must fit below the menu bar. We measure the content
    /// and, if it is taller than the screen, enable a shared fixed-height scroll —
    /// protection against any future module growth, not per-module caps.
    private var maxPanelHeight: CGFloat {
        ((NSScreen.main?.visibleFrame.height) ?? 800) - 24
    }

    private var panelBody: some View {
        Group {
            if panelContentHeight == 0 {
                // Pre-measurement (first ever open): render at natural height so the
                // popover opens correctly; the async height update flips us to the
                // ScrollView below at the SAME height — seamless, and only once.
                panelStack
            } else {
                // One stable ScrollView from then on — never flip between a bare
                // stack and a scrolled one. That flip tore down and rebuilt the WHOLE
                // panel when a torrent unfolded past the screen cap (the popover
                // collapsed and reappeared lower — Anton). Height tracks the measured
                // content up to the cap; scrolling stays inert until the content
                // exceeds it. This is the single scroll for the whole panel.
                ScrollView(showsIndicators: false) {
                    panelStack
                }
                .frame(width: 368, height: min(panelContentHeight, maxPanelHeight))
                .scrollDisabled(panelContentHeight <= maxPanelHeight)
            }
        }
        .onReceive(model.$openTab) { target in
            guard let target else { return }
            overlayReturnScreen = nil
            iconPickerTabID = nil
            let resolved = Self.resolve(target)
            screen = resolved
            if case .space(let id) = resolved { activeSpaceRaw = id.uuidString }
            model.openTab = nil
        }
    }

    // MARK: - "What's new" announcement banner (top of the panel, above the tabs)

    private struct FeatureAnnouncement {
        let id: String          // seen flag lives at featureSeen.<id>
        let moduleKey: String   // UserDefaults toggle flipped on "enable"
        let title: L10nKey
        let body: L10nKey
    }
    // New features are appended here as the app gains them; each shows a one-time
    // top-of-panel banner to users who updated into it.
    private static let featureAnnouncements: [FeatureAnnouncement] = [
        .init(id: "torrent", moduleKey: "showTorrentModule",
              title: .featureTorrentTitle, body: .featureTorrentBody)
    ]

    /// The first announcement the user hasn't acted on (enabled or hidden). In a
    /// snapshot it's forced on by `--feature-banner` so the design can be reviewed.
    private var pendingAnnouncement: FeatureAnnouncement? {
        if Snapshot.active {
            let wantsBanner = CommandLine.arguments.contains("--feature-banner")
                || CommandLine.arguments.contains("--feature-banner-step2")
            return wantsBanner ? Self.featureAnnouncements.first : nil
        }
        return torrentFeatureSeen ? nil : Self.featureAnnouncements.first
    }

    /// Two-step announcement (Anton, 2026-07-18). Updaters got the module OFF and
    /// need a real opt-in, not just a visibility toggle:
    ///  step 1 — "new · torrents" + description + the honest cost ("enabling
    ///           downloads the engine, ~26 MB") with [enable] / [hide];
    ///  step 2 — enable starts the background engine fetch and the SAME card
    ///           swaps to the follow-up settings: show-when-empty and
    ///           default-handler toggles + save.
    @ViewBuilder private var featureBanner: some View {
        if let ann = pendingAnnouncement {
            VStack(alignment: .leading, spacing: 0) {
                // "new · <feature>" in ONE type size — the badge used to be two
                // points smaller and read as detached from the feature name.
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accentGreen)
                    Text(t(.featureNewBadge))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.accentGreen)
                    Text("·").foregroundStyle(Theme.textTertiary)
                    Text(t(ann.title))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                }
                if bannerEnabled {
                    bannerFollowUp(ann)
                } else {
                    bannerOptIn(ann)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.accentGreen.opacity(0.35), lineWidth: 1))
        }
    }

    /// Step 1: the pitch, the price, and the decision.
    @ViewBuilder private func bannerOptIn(_ ann: FeatureAnnouncement) -> some View {
        Text(t(ann.body))
            .font(Theme.mono(10))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 5)
        // Honest cost of saying yes — BEFORE the choice, not after.
        Text(t(.torrentEngineNote))
            .font(Theme.mono(9))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 3)
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            Button {
                UserDefaults.standard.set(true, forKey: "featureSeen.\(ann.id)")
                torrentFeatureSeen = true   // module stays off, banner drops away
            } label: {
                HoverLabel(text: t(.featureHide), size: 10, color: Theme.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                UserDefaults.standard.set(true, forKey: ann.moduleKey)
                // Opting in = fetch the engine NOW (background), so the first
                // real download doesn't stall behind a surprise 26 MB install.
                model.torrent.prefetchEngineIfNeeded()
                bannerEnabled = true        // same card swaps to follow-up settings
            } label: {
                Text(t(.featureEnable))
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundStyle(Theme.playFg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverDim()
        }
        .padding(.top, 12)
    }

    /// Step 2: the engine is fetching in the background; the card becomes the
    /// module's two follow-up choices.
    @ViewBuilder private func bannerFollowUp(_ ann: FeatureAnnouncement) -> some View {
        // Live engine progress while it downloads; silent once installed.
        if let progress = bannerEngineProgress {
            Text(progress)
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 5)
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(t(.torrentShowWhenEmpty))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Theme.MiniSwitch(isOn: $torrentShowWhenEmpty)
            }
            HStack {
                Text(t(.torrentMakeDefault))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Theme.MiniSwitch(isOn: $bannerMakeDefault)
            }
        }
        .padding(.top, 14)
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button { saveAnnouncement(ann) } label: {
                Text(t(.featureSave))
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundStyle(Theme.playFg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverDim()
        }
        .padding(.top, 12)
    }

    /// One dim line of engine-install progress for the banner's step 2, nil once
    /// the engine is in place. The snapshot variant fakes mid-download so the
    /// state can be design-reviewed.
    private var bannerEngineProgress: String? {
        if Snapshot.active, CommandLine.arguments.contains("--feature-banner-step2") {
            return "\(t(.torrentGetting)) · 26 MB · 45%"
        }
        switch model.torrent.installer.state {
        case .downloading(let p):
            return "\(t(.torrentGetting)) · \(Int(p * 100))%"
        case .verifying:
            return t(.torrentVerifying)
        default:
            return nil
        }
    }

    private func saveAnnouncement(_ ann: FeatureAnnouncement) {
        if bannerMakeDefault { makeHopDefaultForTorrent() }
        UserDefaults.standard.set(true, forKey: "featureSeen.\(ann.id)")
        torrentFeatureSeen = true   // re-render: the banner drops away
    }

    private var panelStack: some View {
        VStack(spacing: 16) {
            featureBanner
            header
            switch screen {
            case .space(let rawID):
                // resolve a possibly-dead id (its space may have been deleted
                // from the settings window since this panel was built)
                let id = effectiveSpaceID(rawID)
                let modules = visibleModules(in: id)
                if modules.isEmpty {
                    Text(t(.tabEmptyHint))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                } else {
                    // a stack of the space's modules in order. Inner spacing equals
                    // the outer one (16): the divider sits exactly midway between
                    // modules, with equal space above and below
                    ForEach(Array(modules.enumerated()), id: \.element) { index, key in
                        if index == 0 {
                            moduleBlock(key, in: id)
                        } else {
                            VStack(spacing: 16) {
                                Rectangle()
                                    .fill(Theme.divider)
                                    .frame(height: 1)
                                moduleBlock(key, in: id)
                            }
                        }
                    }
                }
            case .settings:
                settingsScreen
            case .about:
                aboutScreen
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(width: 368)
        .background(Theme.panelBackground)
        .background(GeometryReader { geo in
            Color.clear
                // IMPORTANT: mutate state OUTSIDE the current layout pass —
                // assigning directly from GeometryReader flipped the Group
                // branch during AppKit's layout cycle, NSHostingView threw an
                // NSException and the app crashed (the "timer tab" crash)
                .onAppear { updatePanelHeight(geo.size.height) }
                .onChange(of: geo.size.height) { _, h in updatePanelHeight(h) }
        })
        .simultaneousGesture(TapGesture().onEnded {
            // a click outside the display clears the digit-group selection (yellow highlight = focus)
            let tappedAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                if lastDisplayTap < tappedAt {
                    editUnit = nil
                }
                // every resolved click may change who owns the keyboard:
                // the controller hands focus back to the app underneath
                // unless the panel is actually typing (digits/search)
                model.panelFocusChanged?()
            }
        })
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { press in
            handleKey(press)
        }
        .onChange(of: editUnit) { _, unit in
            model.panelKeyboardCaptured = unit != nil
            if unit == nil { model.panelFocusChanged?() }
        }
        .onDisappear {
            model.panelKeyboardCaptured = false
            // A normal left-click / hotkey reopen does not fire the openTab
            // handler (openTab stays nil), and @State survives the popover
            // hide/show — so clear the picker here too, or the panel comes
            // back stuck on the icon grid instead of the space.
            iconPickerTabID = nil
        }
    }

    /// Keyboard time entry into the selected digit group: digits slide in from the
    /// right (0 → 2 gives :02). The group is picked by clicking/hovering the display.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard let id = currentSpaceID,
              visibleModules(in: id).contains("timer"),
              !model.engine.isStopwatch,
              model.engine.state == .idle || model.engine.state == .finished
        else { return .ignored }

        if let ch = press.characters.first, ch.isNumber, let d = ch.wholeNumberValue {
            if editUnit == nil { editUnit = 60 } // no selection — edit minutes
            mutateSelectedUnit { ($0 * 10 + d) % 100 }
            return .handled
        }
        switch press.key {
        case .delete:
            mutateSelectedUnit { $0 / 10 }
            return .handled
        case .return, .space:
            editUnit = nil
            model.engine.toggle()
            return .handled
        case .escape:
            editUnit = nil
            return .handled
        default:
            return .ignored
        }
    }

    private func mutateSelectedUnit(_ transform: (Int) -> Int) {
        let unit = editUnit ?? 60
        let total = Int(model.engine.duration)
        var h = total / 3600
        var m = (total % 3600) / 60
        var s = total % 60
        switch unit {
        case 3600: h = transform(h)
        case 60: m = transform(m)
        default: s = transform(s)
        }
        chosenPreset = nil
        Sounds.scrubTick()
        model.engine.setDuration(TimeInterval(h * 3600 + m * 60 + s))
    }

    /// Digit sizes: a single "large/small" setting for all formats
    /// and both layouts (full and compact module row); small is roughly
    /// half of large, so the difference is immediately visible.
    private var digitsLarge: Bool { digitsSize != "small" }
    // +25% per Anton's request; the dots hit the panel width limit:
    // 39 columns × 8.6 ≈ 335 of ~340 available
    // large dots are at the panel width ceiling (39 columns × 8.6 ≈ 335),
    // no room to grow; text and units styles got another +25%
    private var dotCellFull: CGFloat { digitsLarge ? 8.6 : 5.6 }
    private var textSizeFull: CGFloat { digitsLarge ? 62 : 33 }
    private var unitsSizeFull: CGFloat { digitsLarge ? 52 : 29 }
    // compact gets +25% too: its sizes were the ones "not visible" —
    // the setting works in both timer views
    private var dotCellCompact: CGFloat { digitsLarge ? 6.0 : 3.3 }
    private var textSizeCompact: CGFloat { digitsLarge ? 33 : 17.5 }
    private var unitsSizeCompact: CGFloat { digitsLarge ? 29 : 15.5 }

    /// Display in the chosen format. Dots are the signature look;
    /// digit-group highlight and clicks live only in the dots style.
    @ViewBuilder
    private func timeDisplay(text: String, seconds: TimeInterval, compact: Bool,
                             dimCount: Int, blinkOff: Bool) -> some View {
        switch displayStyle {
        case "text":
            Text(text)
                .font(Theme.mono(compact ? textSizeCompact : textSizeFull, weight: .semibold))
                .foregroundStyle(blinkOff ? Theme.dotOff : Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case "units":
            Text(unitsString(seconds))
                .font(Theme.mono(compact ? unitsSizeCompact : unitsSizeFull, weight: .semibold))
                .foregroundStyle(blinkOff ? Theme.dotOff : Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        default:
            DotMatrixDisplay(
                text: text,
                dimCount: dimCount,
                blinkOff: blinkOff,
                cell: compact ? dotCellCompact : dotCellFull,
                highlight: nil // yellow digit-group highlight removed by request
            )
        }
    }

    private func unitsString(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)\(t(.unitHour))") }
        parts.append(String(format: "%02d%@", m, t(.unitMin)))
        parts.append(String(format: "%02d%@", s, t(.unitSec)))
        return parts.joined(separator: " ") // thin space: units do not drift apart
    }

    /// Yellow highlight of the digit group being edited on the display.
    private var editHighlight: Range<Int>? {
        guard model.engine.state == .idle || model.engine.state == .finished,
              let unit = editUnit else { return nil }
        switch unit {
        case 3600: return 0..<2
        case 60: return 3..<5
        default: return 6..<8
        }
    }

    private func selectUnit(atX x: CGFloat, cell: CGFloat) {
        let fallback = CGFloat(DotFont.columns(for: "00:00:00")) * cell
        let width = displayMeasuredWidth > 0 ? displayMeasuredWidth : fallback
        let fraction = x / max(width, 1)
        editUnit = unitForScrub(fraction: fraction)
    }

    /// Digit-group zone by fraction of display width — one logic for all styles.
    /// In the "units" style hours are hidden when zero — the display splits
    /// in half: minutes on the left, seconds on the right.
    private func unitForScrub(fraction: CGFloat) -> TimeInterval {
        if displayStyle == "units", model.engine.remaining < 3600 {
            return fraction < 0.5 ? 60 : 1
        }
        return fraction < 0.31 ? 3600 : (fraction < 0.65 ? 60 : 1)
    }

    /// Visible display width — measured in the background, without affecting layout.
    /// Measured-geometry updates run async and with hysteresis,
    /// to never mutate state inside a layout pass (NSHostingView crash).
    private func updatePanelHeight(_ height: CGFloat) {
        guard abs(height - panelContentHeight) > 1 else { return }
        DispatchQueue.main.async { panelContentHeight = height }
    }

    private func updateDisplayWidth(_ width: CGFloat) {
        guard abs(width - displayMeasuredWidth) > 1 else { return }
        DispatchQueue.main.async { displayMeasuredWidth = width }
    }

    private func reportAboutHeight(_ height: CGFloat) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .init("hopAboutContentHeight"), object: nil,
                userInfo: ["height": height]
            )
        }
    }

    private var displayWidthReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { updateDisplayWidth(geo.size.width) }
                .onChange(of: geo.size.width) { _, w in updateDisplayWidth(w) }
        }
    }

    // MARK: - Header

    private var isOverlayScreen: Bool {
        screen == .settings || screen == .about
    }

    private var header: some View {
        HStack(spacing: 8) {
            if isOverlayScreen {
                overlayHeaderContent(title: screen == .about ? t(.aboutTitle) : t(.settingsTitle)) {
                    screen = overlayReturnScreen ?? Self.resolve(.restore)
                }
            } else {
                // pure switcher: creating/reordering/renaming/deleting tabs all
                // live in settings now, so a stray header click can't spawn a
                // space. The service trio returns to the right.
                tabSwitcher
                Spacer()
                headerIcon("info.circle") {
                    model.openAboutWindow?()
                }
                headerIcon("gearshape") {
                    model.openSettingsWindow?()
                }
                headerIcon("power") {
                    model.requestQuit?()
                }
            }
        }
        .frame(height: 34) // same header height on all screens
    }

    /// Shared back-chevron header used by the settings/about overlays: a "back"
    /// button on the left, a dim screen title on the right.
    @ViewBuilder
    private func overlayHeaderContent(title: String, back: @escaping () -> Void) -> some View {
        Button(action: back) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text(t(.back))
                    .font(Theme.mono(12, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
        Spacer()
        Text(title)
            .font(Theme.mono(10))
            .foregroundStyle(Theme.textTertiary)
    }

    private func headerIcon(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }

    // Tab button geometry. Width is doubled from 32 for a comfortable hit target;
    // at maxTabs (4): 4×56 + inner gaps + the 3-icon service trio still fit the
    // 340pt header content (see report arithmetic).
    private static let tabButtonWidth: CGFloat = 56
    private static let tabSpacing: CGFloat = 2

    // an icon row of the user's spaces, chip-highlighting the active one. Pure
    // switcher: add/reorder/rename/delete all moved to settings, so there is no
    // "+", drag, or context menu here. The stroke container groups the icons.
    private var tabSwitcher: some View {
        HStack(spacing: Self.tabSpacing) {
            ForEach(tabsModel.tabs) { tab in
                spaceTabButton(tab)
            }
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.divider, lineWidth: 1))
    }

    private func spaceTabButton(_ tab: PanelTab) -> some View {
        // compare against the LIVE current space (same derivation the content
        // uses), so the highlight never lands on a deleted id or on nothing
        let active = currentSpaceID == tab.id
        return Image(systemName: tab.icon)
            .font(.system(size: 15))
            .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
            .frame(width: Self.tabButtonWidth, height: 28)
            .background(
                active ? Theme.chipBg : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
            .hoverHighlight(6)
            .onTapGesture { switchToSpace(tab.id) }
    }

    /// First catalog icon no tab already uses (fallback: the first entry), so a
    /// new tab does not duplicate an existing icon at birth.
    private var firstUnusedIcon: String {
        let used = Set(tabsModel.tabs.map(\.icon))
        return IconCatalog.symbols.first { !used.contains($0) } ?? IconCatalog.symbols[0]
    }

    /// How far a resting settings tab-row steps aside to open a gap at the drop
    /// target. Vertical, fixed `moduleRowHeight` — same math as the module rows.
    private func tabRowShift(_ index: Int) -> CGFloat {
        guard let id = dragTabID,
              let from = tabsModel.tabs.firstIndex(where: { $0.id == id }),
              let target = dragTabTarget, index != from else { return 0 }
        if from < index, target >= index { return -Self.moduleRowHeight }
        if from > index, target <= index { return Self.moduleRowHeight }
        return 0
    }

    private func tabRowDragGesture(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let tabs = tabsModel.tabs
                guard let from = tabs.firstIndex(where: { $0.id == id }) else { return }
                if dragTabID == nil {
                    dragTabID = id
                    dragTabTarget = from
                    // an open picker adds height to one row and breaks the
                    // uniform-row-height drag math visually — fold it first
                    iconPickerTabID = nil
                }
                dragTabOffset = value.translation.height
                let steps = Int((value.translation.height / Self.moduleRowHeight).rounded())
                let target = min(max(from + steps, 0), tabs.count - 1)
                if target != dragTabTarget {
                    dragTabTarget = target
                    Sounds.scrubTick()
                }
            }
            .onEnded { _ in
                let from = tabsModel.tabs.firstIndex(where: { $0.id == id })
                // commit and settle together: the visual offset is close to the
                // committed displacement, so the row glides rather than jumps
                withAnimation(.easeInOut(duration: 0.15)) {
                    if let from, let target = dragTabTarget, target != from {
                        mutateTabs { $0.moveTab(from: from, to: target) }
                    }
                    dragTabID = nil
                    dragTabTarget = nil
                    dragTabOffset = 0
                }
            }
    }

    /// Delete a tab from settings. HopCore folds the deleted tab's modules into
    /// the first tab, so nothing is lost — no confirmation needed. Settings is a
    /// separate window, so this can't touch the live panel screen; instead clear
    /// the saved active space if it pointed at the deleted tab, so the panel
    /// reopens on a valid space (screen resolution falls back to tabs[0]).
    private func deleteTab(_ id: UUID) {
        mutateTabs { $0.deleteTab(id) }
        if activeSpaceRaw == id.uuidString { activeSpaceRaw = "" }
        // in-panel path (if ever shown there): fall back off the deleted space
        if screen == .space(id), let first = tabsModel.tabs.first {
            switchToSpace(first.id)
        }
        // a stale inline picker for the gone tab would dangle open
        if iconPickerTabID == id { iconPickerTabID = nil }
    }

    private func switchToSpace(_ id: UUID) {
        screen = .space(id)
        activeSpaceRaw = id.uuidString
    }

    /// One settings row for a tab: drag handle, the icon (tapping it toggles the
    /// inline picker for this tab), its "#N" position, and a delete xmark
    /// (hidden for the last remaining tab). The row drag-reorders vertically.
    @ViewBuilder private func tabSettingsRow(_ tab: PanelTab, index: Int) -> some View {
        let dragged = dragTabID == tab.id
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // drag handle: two lines, left-aligned (same as module rows)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().frame(width: 11, height: 1.5)
                    Capsule().frame(width: 11, height: 1.5)
                }
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 14, height: 18, alignment: .leading)
                Button {
                    iconPickerTabID = (iconPickerTabID == tab.id) ? nil : tab.id
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(5)
                .help(t(.tabChangeIcon).capitalizedFirst)
                Text("#\(index + 1)")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if tabsModel.tabs.count > 1 {
                    Button { deleteTab(tab.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(5)
                    .help(t(.tabDelete).capitalizedFirst)
                }
            }
            .padding(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 2))
            .frame(height: Self.moduleRowHeight)
            .contentShape(Rectangle())
            .opacity(dragged ? 0.4 : 1)
            .offset(y: dragged ? dragTabOffset : tabRowShift(index))
            .zIndex(dragged ? 1 : 0)
            .animation(dragged ? nil : .easeInOut(duration: 0.15), value: tabRowShift(index))
            .gesture(tabRowDragGesture(tab.id))

            if iconPickerTabID == tab.id {
                iconPickerGrid(for: tab.id)
            }
        }
    }

    /// "add tab" row below the tab list — the deliberate second step (open
    /// settings, then click) that keeps spaces from being created by accident.
    private var addTabRow: some View {
        Button {
            // deliberately does NOT switch the panel to the new space: creation
            // is a settings action, not navigation.
            mutateTabs { $0.addTab(icon: firstUnusedIcon) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .frame(width: 14, alignment: .leading)
                Text(t(.tabNew))
                    .font(Theme.mono(12))
                Spacer()
            }
            .foregroundStyle(Theme.textTertiary)
            .padding(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 2))
            .frame(height: Self.moduleRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(5)
    }

    /// Icon picker grid, shown inline under a tab's settings row. Inline rather
    /// than a nested popover (which risks dismissing the panel) or a panel-level
    /// overlay (settings is a standalone window that renders `settingsScreen`
    /// directly, so an overlay keyed off the panel stack never appears there).
    private func iconPickerGrid(for tabID: UUID) -> some View {
        let current = tabsModel.tabs.first { $0.id == tabID }?.icon
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
            spacing: 8
        ) {
            ForEach(IconCatalog.symbols, id: \.self) { symbol in
                Button {
                    mutateTabs { $0.setIcon(symbol, tabID: tabID) }
                    iconPickerTabID = nil
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(symbol == current ? Theme.textPrimary : Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            symbol == current ? Theme.chipBg : .clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(6)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Presets

    private var presetsRow: some View {
        HStack {
            if timerCompact {
                // compact: presets only (time is set by dragging the display)
                HStack(spacing: 12) {
                    ForEach(presets, id: \.self) { minutes in
                        presetButton(minutes)
                    }
                }
                if let stash = model.engine.stash {
                    restoreButton(stash)
                }
                Spacer()
                stopwatchToggle
            } else {
                adjustButton(label: "−5 \(t(.minUnit))", delta: -TimerEngine.step)
                Spacer()
                HStack(spacing: 12) {
                    ForEach(presets, id: \.self) { minutes in
                        presetButton(minutes)
                    }
                }
                Spacer()
                adjustButton(label: "+5 \(t(.minUnit))", delta: TimerEngine.step)
                stopwatchToggle
            }
        }
    }

    private func nudgeStopFirst() {
        // exactly TWO stroke pulses, opacity only (no scaling).
        // The value animates back to false — no third
        // "fast" blink from a hard reset at the end.
        let pulse = Animation.easeInOut(duration: 0.18)
        withAnimation(pulse) { stopHintPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(pulse) { stopHintPulse = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            withAnimation(pulse) { stopHintPulse = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            withAnimation(pulse) { stopHintPulse = false }
        }
    }

    /// Timer ↔ stopwatch: in stopwatch mode time counts up from zero.
    private var stopwatchToggle: some View {
        let active = model.engine.isStopwatch
        return Button {
            // while running — a "press pause" hint; switching from pause is
            // allowed: the timer is already stopped, the mode change is deliberate
            if model.engine.state == .running {
                nudgeStopFirst()
            } else {
                model.engine.setStopwatch(!active)
            }
        } label: {
            Image(systemName: "stopwatch")
                .font(.system(size: 12))
                .foregroundStyle(active ? Theme.editing : Theme.textTertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .help(t(.stopwatchLabel))
    }

    // MARK: - Work-rest cycles

    private var cyclesRow: some View {
        HStack(spacing: 8) {
            // templates on the left: "work/rest ×rounds"
            HStack(spacing: 12) {
                ForEach(Array(cycleTemplates.enumerated()), id: \.offset) { _, template in
                    Button {
                        // same as presets: hint while a countdown is active
                        if model.engine.state == .running || model.engine.state == .paused {
                            nudgeStopFirst()
                            return
                        }
                        chosenPreset = nil
                        model.engine.prepareCycle(
                            work: TimeInterval(template.work * 60),
                            rest: TimeInterval(template.rest * 60),
                            rounds: template.rounds
                        )
                    } label: {
                        HoverLabel(text: "\(template.work)/\(template.rest) ×\(template.rounds)")
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 4)
            // cycle status on the right; color = state:
            // yellow — armed, green — work, cyan — rest, orange — paused
            if let cycle = model.engine.cycle {
                let color: Color = switch model.engine.state {
                case .idle, .finished: Theme.editing
                case .paused: Theme.accentOrange
                case .running: cycle.isWork ? Theme.accentGreen : Theme.accentCyan
                }
                Text("\(t(cycle.isWork ? .workLabel : .restLabel)) \(cycle.round)/\(cycle.rounds)")
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    // MARK: - Compact timer (default)

    private var compactTimer: some View {
        let engine = model.engine
        let text = TimeFormatting.display(engine.isStopwatch ? engine.elapsed : engine.remaining)
        let state = model.engine.state
        let finished = state == .finished
        let running = state == .running
        let isStart = state == .idle || finished
        return HStack(spacing: 8) {
            // start button on the left, before the display
            Button {
                model.engine.toggle()
            } label: {
                Image(systemName: running ? "pause.fill" : "play.fill")
                    // the transport tracks the DIGIT SIZE setting, not the layout:
                    // big digits deserve the big button, small ones the small
                    .font(.system(size: digitsLarge ? 12 : 10, weight: .semibold))
                    .foregroundStyle(isStart ? Theme.playFg : Theme.textPrimary)
                    .frame(width: digitsLarge ? 34 : 27, height: digitsLarge ? 34 : 27)
                    .background(isStart ? Theme.playBg : .clear, in: Circle())
                    .overlay {
                        if running {
                            PulsingRing() // countdown running — the button "breathes"
                        } else if !isStart {
                            Circle().stroke(Theme.controlStroke, lineWidth: 1.5)
                        }
                    }
                    .overlay {
                        Circle()
                            .stroke(Theme.textPrimary, lineWidth: 2)
                            .opacity(stopHintPulse ? 0.9 : 0)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hoverDim()
            if state != .idle {
                // reset — right next to start
                Button {
                    model.engine.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: digitsLarge ? 11 : 9, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: digitsLarge ? 26 : 21, height: digitsLarge ? 26 : 21)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight()
            }
            Spacer(minLength: 6)
            // digits on the right, with breathing room from the buttons
            timeDisplay(
                text: text,
                seconds: engine.isStopwatch ? engine.elapsed : engine.remaining,
                compact: true,
                dimCount: finished ? 0 : TimeFormatting.dimCount(for: text),
                blinkOff: finished && !model.blinkOn
            )
            .background(displayWidthReader)
            .contentShape(Rectangle())
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                if engine.state == .finished {
                    engine.reset() // "okay, got it" — same as on the large display
                    return
                }
                guard !engine.isStopwatch, displayStyle == "dots" else { return }
                lastDisplayTap = Date()
                selectUnit(atX: value.location.x, cell: dotCellCompact)
            })
            .simultaneousGesture(scrubGesture(cell: dotCellCompact))
            .help(engine.isStopwatch ? t(.stopwatchLabel) : t(.dragToSet))
            if engine.isStopwatch || !showPresetsRow {
                // in stopwatch mode the presets row is hidden; with templates hidden
                // the toggle must not vanish either — fit it into this same row
                stopwatchToggle
            }
        }
        .padding(.vertical, 2)
    }

    private func adjustButton(label: String, delta: TimeInterval) -> some View {
        Button {
            Sounds.scrubTick()
            model.engine.adjust(by: delta)
        } label: {
            Text(label)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.divider, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func presetButton(_ minutes: Int) -> some View {
        // highlight only an explicitly chosen preset: custom time
        // and armed cycles leave the numbers untouched
        let isActive = chosenPreset == minutes
            && model.engine.state == .idle
            && model.engine.cycle == nil
            && model.engine.duration == TimeInterval(minutes * 60)
        return Button {
            // while a countdown is active the template does not apply — stop first
            // (an accidental click must not reset a running timer)
            if model.engine.state == .running || model.engine.state == .paused {
                nudgeStopFirst()
                return
            }
            chosenPreset = minutes
            model.engine.setPreset(minutes: minutes)
        } label: {
            HoverLabel(
                text: "\(minutes)",
                size: 11,
                weight: isActive ? .bold : .medium,
                color: isActive ? Theme.textPrimary : Theme.textTertiary
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func restoreButton(_ stash: TimerEngine.Stash) -> some View {
        Button {
            model.engine.restoreStash()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 8, weight: .semibold))
                Text(TimeFormatting.short(stash.remaining))
                    .font(Theme.mono(10))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Theme.divider, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var resetButton: some View {
        Button {
            model.engine.reset()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9, weight: .semibold))
                Text("reset")
                    .font(Theme.mono(9))
            }
            .foregroundStyle(Theme.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Display

    private var display: some View {
        let text = TimeFormatting.display(model.engine.remaining)
        let state = model.engine.state
        let finished = state == .finished
        let scrubbable = state == .idle || state == .finished
        return VStack(spacing: 6) {
            timeDisplay(
                text: text,
                seconds: model.engine.remaining,
                compact: false,
                dimCount: finished ? 0 : TimeFormatting.dimCount(for: text),
                blinkOff: finished && !model.blinkOn
            )
            .background(displayWidthReader)
            .contentShape(Rectangle())
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                // "okay, got it": clicking the blinking digits silences the ring
                // and returns the timer to the set time
                if model.engine.state == .finished {
                    model.engine.reset()
                    return
                }
                guard displayStyle == "dots" else { return }
                lastDisplayTap = Date()
                selectUnit(atX: value.location.x, cell: dotCellFull)
            })
            .simultaneousGesture(scrubGesture(cell: dotCellFull))
            .help(t(.dragToSet))
            // fixed row under the display: hint ↔ reset, with the stash next to it
            HStack(spacing: 14) {
                if !scrubbable {
                    resetButton
                }
                if let stash = model.engine.stash {
                    restoreButton(stash)
                }
            }
            .frame(height: 18)
        }
        .padding(.top, 6)
    }

    /// Scrubbing on the display: dragging over hours/minutes/seconds spins that digit group.
    /// Overflow carries over by itself — everything is computed in seconds internally.
    private func scrubGesture(cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !model.engine.isStopwatch else { return }
                guard model.engine.state == .idle || model.engine.state == .finished else { return }
                if scrubBaseDuration == nil {
                    scrubBaseDuration = model.engine.duration
                    // digit group — from the point where the drag started: HH | MM | SS;
                    // width — measured on the visible display (any style)
                    let fallback = CGFloat(DotFont.columns(for: "00:00:00")) * cell
                    let width = displayMeasuredWidth > 0 ? displayMeasuredWidth : fallback
                    let fraction = value.startLocation.x / max(width, 1)
                    scrubUnit = unitForScrub(fraction: fraction)
                    editUnit = scrubUnit
                }
                let unit = scrubUnit ?? 60
                let pxPerStep: CGFloat = unit == 3600 ? 14 : (unit == 60 ? 7 : 3)
                // scrubbing works in any direction: right/up — more,
                // left/down — less; on a diagonal take the dominant axis
                // so the speed does not double
                let dx = value.translation.width
                let dy = -value.translation.height
                let travel = abs(dx) >= abs(dy) ? dx : dy
                let steps = (travel / pxPerStep).rounded()
                let newDuration = (scrubBaseDuration ?? 0) + Double(steps) * unit
                if newDuration != model.engine.duration {
                    chosenPreset = nil // custom time — no preset highlight
                    Sounds.scrubTick() // quiet ratchet tick on each step
                }
                model.engine.setDuration(newDuration)
            }
            .onEnded { _ in
                scrubBaseDuration = nil
                scrubUnit = nil
            }
    }

    // MARK: - Transport

    private var transport: some View {
        playPauseButton // the only button at the bottom, centered
    }

    private var playPauseButton: some View {
        let state = model.engine.state
        let running = state == .running
        let isStart = state == .idle || state == .finished
        return Button {
            model.engine.toggle()
        } label: {
            Image(systemName: running ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isStart ? Theme.playFg : Theme.textPrimary)
                .frame(width: 48, height: 48)
                .background(isStart ? Theme.playBg : .clear, in: Circle())
                .overlay {
                    if running {
                        PulsingRing()
                    } else if !isStart {
                        Circle().stroke(Theme.controlStroke, lineWidth: 1.5)
                    }
                }
                .overlay {
                    Circle()
                        .stroke(Theme.textPrimary, lineWidth: 2)
                        .opacity(stopHintPulse ? 0.9 : 0)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Converter

    private var convertZone: some View {
        Button {
            model.openConverterWindow?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.zipper")
                    .font(.system(size: 12))
                    .foregroundStyle(dropTargeted ? Theme.editing : Theme.textSecondary)
                Text("\(t(.convertLabel)) · \(t(.convCompressOnly))")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(dropTargeted ? Theme.editing : .clear, lineWidth: 1)
        )
        .hoverHighlight(7)
        .snapshotAwareDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await loadFileURL(provider) {
                        urls.append(url)
                    }
                }
                model.converter.addToBatch(urls)
                model.openConverterWindow?()
            }
            return true
        }
    }

    // MARK: - Main screen modules

    // "system"/"tracker" are deliberately NOT here: they live only in the tabs
    // model (the fixed monitor tab from `migrate`, and a later module). Adding
    // "system" would make `moduleOrder` append it AND `migrate` place it in its
    // own tab — a duplicate key the tabs model rejects.
    private static let allModules = ["timer", "awake", "clipboard", "convert", "windows", "speedtest", "torrent"]
    static let defaultModuleOrder = "timer,awake,clipboard,convert,windows,speedtest,torrent"

    private var moduleOrder: [String] {
        Self.normalizedOrder(moduleOrderRaw)
    }

    private static func normalizedOrder(_ raw: String) -> [String] {
        var order = raw.split(separator: ",").map(String.init)
            .filter { allModules.contains($0) }
        for key in allModules where !order.contains(key) {
            order.append(key)
        }
        return order
    }

    /// Current spaces model: stored JSON if valid, otherwise migrated from the
    /// legacy flat module order. New module keys are appended on the fly so an
    /// app update never loses a module.
    private var tabsModel: PanelTabsModel {
        Self.loadTabs(panelTabsRaw: panelTabsRaw, moduleOrder: moduleOrder)
    }

    /// Decodes the stored tabs, or migrates from the legacy order on first
    /// launch. The migrated model is persisted immediately: `migrate` mints
    /// fresh UUIDs on every call, so without persisting, the tab id captured in
    /// `screen` (resolved once, in `init`) would never match a later read of the
    /// model and the space would render empty. Shared by the instance property
    /// and the `init`-time resolver so both see the same, stable ids.
    private static func loadTabs(panelTabsRaw: String, moduleOrder: [String]) -> PanelTabsModel {
        if let decoded = PanelTabsModel.decode(panelTabsRaw) {
            var model = decoded
            model.ensure(modules: allModules + ["system", "tracker"])
            return model
        }
        var model = PanelTabsModel.migrate(moduleOrder: moduleOrder)
        model.ensure(modules: allModules + ["system", "tracker"])
        UserDefaults.standard.set(model.encoded(), forKey: SettingsKey.panelTabs)
        return model
    }

    /// The tabs model read straight from UserDefaults — usable from `init`,
    /// before the @AppStorage wrappers are readable. The panel content view is
    /// built once at launch, so this matches how `initialTab` resolved before.
    private static func storedTabsModel() -> PanelTabsModel {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: SettingsKey.panelTabs) ?? ""
        let orderRaw = defaults.string(forKey: "moduleOrder") ?? defaultModuleOrder
        return loadTabs(panelTabsRaw: raw, moduleOrder: normalizedOrder(orderRaw))
    }

    /// Resolves a requested initial screen against the stored tabs. The stored
    /// model always has at least one tab, so `tabs[0]` is a safe fallback.
    private static func resolve(_ initial: InitialScreen) -> Screen {
        switch initial {
        case .settings: return .settings
        case .about: return .about
        case .firstSpace:
            return .space(storedTabsModel().tabs[0].id)
        case .spaceContaining(let module):
            let model = storedTabsModel()
            return .space(model.tabID(containing: module) ?? model.tabs[0].id)
        case .restore:
            let model = storedTabsModel()
            let saved = UserDefaults.standard.string(forKey: "activeSpaceID") ?? ""
            if let id = UUID(uuidString: saved), model.tabs.contains(where: { $0.id == id }) {
                return .space(id)
            }
            return .space(model.tabs[0].id)
        }
    }

    private func mutateTabs(_ body: (inout PanelTabsModel) -> Void) {
        var model = tabsModel
        body(&model)
        panelTabsRaw = model.encoded()
    }

    private func visibleModules(in id: UUID) -> [String] {
        (tabsModel.tabs.first { $0.id == id }?.moduleKeys ?? [])
            .filter { moduleVisible($0) }
    }

    /// The space id to actually render and highlight for a stored `screen` id.
    /// The panel is built once at launch and `screen` only resolves in `init`,
    /// so a space deleted meanwhile (from the standalone settings window, a
    /// separate PanelView instance) leaves a dead id in this instance's state.
    /// Derive the live id at every read site — do NOT mutate `@State` in body —
    /// so the rendered content and the tab highlight always agree. `tabs` is
    /// never empty (the model guarantees 1...maxTabs), so `tabs[0]` is safe.
    private func effectiveSpaceID(_ id: UUID) -> UUID {
        tabsModel.tabs.contains { $0.id == id } ? id : tabsModel.tabs[0].id
    }

    /// The live space currently shown, or nil when the panel isn't on a space.
    private var currentSpaceID: UUID? {
        if case .space(let id) = screen { return effectiveSpaceID(id) }
        return nil
    }

    private func moduleVisible(_ key: String) -> Bool {
        switch key {
        case "timer": return showTimerModule
        case "awake": return showAwakeModule
        case "clipboard": return showClipboardModule
        case "convert": return showConvertModule
        case "windows": return showWindowsModule
        case "speedtest": return showSpeedtestModule
        case "torrent":
            guard showTorrentModule else { return false }
            // When installed with zero torrents, the empty add-card is optional:
            // hide the whole module (and its divider) unless the user keeps it on.
            if model.torrent.torrents.isEmpty,
               case .installed = model.torrent.installer.state,
               !torrentShowWhenEmpty {
                return false
            }
            return true
        case "system": return showSystemModule
        case "tracker": return showTrackerModule
        default: return false
        }
    }

    private func moduleBinding(_ key: String) -> Binding<Bool> {
        switch key {
        case "timer": return $showTimerModule
        case "awake": return $showAwakeModule
        case "clipboard": return $showClipboardModule
        case "convert": return $showConvertModule
        case "speedtest": return $showSpeedtestModule
        case "torrent":
            // Turning the module ON in settings also opts into torrents:
            // fetch the engine right away (same as the banner/onboarding path).
            return Binding(
                get: { showTorrentModule },
                set: { on in
                    showTorrentModule = on
                    if on { model.torrent.prefetchEngineIfNeeded() }
                }
            )
        case "system": return $showSystemModule
        case "tracker": return $showTrackerModule
        default: return $showWindowsModule
        }
    }

    private func moduleTitle(_ key: String) -> String {
        switch key {
        case "timer": return t(.aboutTabTimer)
        case "awake": return t(.awakeOff)
        case "clipboard": return t(.tabClipboard)
        case "convert": return t(.convertLabel)
        case "windows": return t(.windowsLabel)
        case "speedtest": return t(.speedtestLabel)
        case "torrent": return t(.torrentLabel)
        case "system": return t(.tabSystem)
        case "tracker": return t(.trackerLabel)
        default: return key
        }
    }


    @ViewBuilder private func moduleContent(_ key: String) -> some View {
        switch key {
        case "timer": timerModule
        case "awake": keepAwakeSection
        case "clipboard":
            ClipboardView(clipboard: model.clipboard, lang: lang, closePanel: { model.closePanel?() })
                .id(model.themeVersion)
        case "convert": convertZone
        case "windows": windowSnapRow
        case "speedtest": speedtestRow
        case "torrent":
            TorrentView(torrent: model.torrent, lang: lang)
                .id(model.themeVersion)
        case "system":
            StatsView(stats: model.stats, lang: lang)
                .id(model.themeVersion)
        case "tracker":
            TrackerView(tracker: model.tracker, lang: lang)
                .id(model.themeVersion)
        default: EmptyView()
        }
    }

    /// A panel module wrapped with its right-click "move to …" menu, one item
    /// per OTHER tab. The wrap lives on the module container, so a module's own
    /// inner context menus/gestures win locally. With a single tab there is
    /// nowhere to move to, so the menu is omitted rather than shown empty.
    @ViewBuilder private func moduleBlock(_ key: String, in tabID: UUID) -> some View {
        let others = tabsModel.tabs.enumerated().filter { $0.element.id != tabID }
        if others.isEmpty {
            moduleContent(key)
        } else {
            moduleContent(key)
                .contextMenu {
                    Menu(t(.moduleMoveTo).capitalizedFirst) {
                        ForEach(others, id: \.element.id) { index, tab in
                            Button {
                                mutateTabs { $0.move(module: key, toTab: tab.id) }
                            } label: {
                                Label("#\(index + 1)", systemImage: tab.icon)
                            }
                        }
                    }
                }
        }
    }

    private var timerModule: some View {
        VStack(spacing: 16) {
            if !model.engine.isStopwatch {
                if showPresetsRow || showCyclesRow {
                    VStack(spacing: 3) {
                        if showPresetsRow {
                            presetsRow
                        }
                        if showCyclesRow {
                            cyclesRow
                        }
                    }
                }
            } else if !timerCompact, showPresetsRow {
                presetsRow // in large mode the toggle lives in this row
            }
            // the stopwatch toggle does not depend on template visibility:
            // with the presets row hidden it gets its own thin row (in compact —
            // right in the timer row, see compactTimer)
            if !showPresetsRow, !timerCompact {
                HStack {
                    Spacer()
                    stopwatchToggle
                }
            }
            if timerCompact {
                compactTimer
            } else {
                VStack(spacing: 8) {
                    display
                    transport
                }
            }
        }
    }

    // MARK: - Speed test

    private var speedtestRow: some View {
        let speed = model.speedTest
        // tight spacing: every language should fit the label without an ellipsis
        return HStack(spacing: 6) {
            Image(systemName: "speedometer")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text(t(.speedtestLabel))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer()
            Group {
                if speed.isRunning {
                    // live digits from the pty + honest seconds
                    let down = speed.liveDown.map { speedValueText($0) } ?? "—"
                    let up = speed.liveUp.map { speedValueText($0) } ?? "—"
                    Text("↓ \(down) · ↑ \(up) · \(speed.elapsed)s")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    ProgressView()
                        .controlSize(.small)
                } else if let last = speed.last {
                    // stale (30+ min or a different network) — barely visible.
                    // RPM right in the row: responsiveness under load,
                    // hiding it in a tooltip felt dishonest
                    Text("\(speedPairText(down: last.down, up: last.up)) · \(last.rpm) RPM")
                        .font(Theme.mono(10))
                        // an old measurement stays readable but clearly "faded"
                        .foregroundStyle(speed.isStale ? Theme.textTertiary.opacity(0.45) : Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .help("\(t(.speedResponsiveness)): \(last.rpm) RPM")
                    if !Snapshot.active {
                        // hidden in product-page screenshots: the row reaches
                        // the panel edge and reads as broken alignment
                        speedRefreshIcon
                    }
                } else if speed.failed {
                    Text(t(.speedtestFail))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textTertiary)
                    speedRefreshIcon
                } else {
                    // the first button is light, like the other text actions
                    Button {
                        model.speedTest.run()
                    } label: {
                        HoverLabel(text: t(.speedtestRun), size: 10, color: Theme.textTertiary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 24) // row height does not shift between states
        }
    }

    /// Speed with its own unit: a slow upload does not hide
    /// behind a generic "Mbps" (620 Kbps instead of "1").
    private func speedValueText(_ mbps: Double) -> String {
        if mbps >= 10 { return "\(Int(mbps.rounded())) \(t(.unitMbps))" }
        if mbps >= 1 { return String(format: "%.1f %@", mbps, t(.unitMbps)) }
        return "\(Int((mbps * 1000).rounded())) \(t(.unitKbps))"
    }

    /// "↓ 834 Mbps · ↑ 112 Mbps" — every value carries its OWN unit
    /// (a bare number is ambiguous, and the two can differ: Kbit/s vs
    /// Mbit/s); thin spaces keep the row compact enough for the label
    private func speedPairText(down: Double, up: Double) -> String {
        "↓ \(speedValueText(down)) · ↑ \(speedValueText(up))"
    }

    private var speedRefreshIcon: some View {
        Button {
            model.speedTest.run()
        } label: {
            // 12pt — same as all action icons; height 24 centers
            // the glyph within the row rather than on its bottom edge
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 20, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(4)
    }



    // MARK: - Window manager

    private var windowSnapRow: some View {
        // Approved 2026-07-13: the short layout is one row of 8,
        // the full one is TWO rows of 8. Rows must be exactly equal length,
        // otherwise Spacers stretch the shorter row and columns drift.
        let essentials: [WindowSnapController.Position] =
            [.leftHalf, .rightHalf, .topHalf, .bottomHalf, .center, .maximize]
        return Group {
            if windowsLayout == "row" {
                // short: 8 zones — no big gaps between buttons
                snapButtonsRow(essentials + [.leftTwoThirds, .rightTwoThirds])
            } else {
                // full: two even rows of 8 (rarely used top/bottom thirds removed)
                VStack(spacing: 6) {
                    snapButtonsRow(essentials + [.leftTwoThirds, .rightTwoThirds])
                    snapButtonsRow([.topLeft, .topRight, .bottomLeft, .bottomRight,
                                    .leftThird, .centerThird, .rightThird, .centerHalf])
                }
            }
        }
    }

    private func snapButtonsRow(_ positions: [WindowSnapController.Position]) -> some View {
        // edge glyphs flush with the panel's overall padding, equal air in between
        HStack(spacing: 0) {
            ForEach(Array(positions.enumerated()), id: \.element) { index, position in
                if index > 0 {
                    Spacer(minLength: 4)
                }
                Button {
                    WindowSnapController.shared.apply(position)
                } label: {
                    snapGlyph(position)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(5)
            }
        }
        .padding(.horizontal, -5) // compensates the inner padding of the edge buttons
    }

    /// Mini zone diagram: screen frame + filled area.
    private func snapGlyph(_ position: WindowSnapController.Position) -> some View {
        Canvas { ctx, size in
            let outer = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            ctx.stroke(
                Path(roundedRect: outer, cornerRadius: 3),
                with: .color(Theme.textTertiary), lineWidth: 1
            )
            // for "center" the glyph fill is smaller than the real zone —
            // otherwise it is indistinguishable from "maximize"
            let u = position == .center
                ? CGRect(x: 0.24, y: 0.2, width: 0.52, height: 0.6)
                : position.unit
            // fill inset is minimal: with a bigger inset "half" collapsed
            // into a sliver at the edge and proportions were unreadable
            let inner = CGRect(
                x: outer.minX + u.minX * outer.width,
                y: outer.minY + (1 - u.maxY) * outer.height,
                width: u.width * outer.width,
                height: u.height * outer.height
            ).insetBy(dx: 1, dy: 1)
            ctx.fill(Path(roundedRect: inner, cornerRadius: 1.5), with: .color(Theme.textSecondary))
        }
        .frame(width: 26, height: 16)
    }

    private func loadFileURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private var converterSettings: some View {
        VStack(spacing: 14) {
            HStack {
                Text(t(.convAutoClearLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Theme.MiniSwitch(isOn: $convAutoClear)
            }

            // format/scale/quality are asked in the converter window itself
            // on every conversion — here only where to put the result
            HStack {
                Text(t(.convDestLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                destChip("downloads", t(.convDestDownloads))
                destChip("same", t(.convDestSame))
                Button {
                    chooseDestinationFolder()
                } label: {
                    Text(convDest == "custom" && !convDestPath.isEmpty
                        ? URL(fileURLWithPath: convDestPath).lastPathComponent
                        : "…")
                        .font(Theme.mono(10))
                        .foregroundStyle(convDest == "custom" ? Theme.textPrimary : Theme.textTertiary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            convDest == "custom" ? Theme.chipBg : .clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(convDest == "custom" ? Theme.controlStroke : Theme.divider, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(5)
            }
        }
    }

    private func convChip(_ raw: String, _ label: String) -> some View {
        settingChip(label, active: convFormat == raw) { convFormat = raw }
    }

    private func scaleChip(_ value: Double) -> some View {
        settingChip(value == 1.0 ? "1×" : String(format: "%.2g×", value), active: convScale == value) {
            convScale = value
        }
    }

    private func destChip(_ raw: String, _ label: String) -> some View {
        settingChip(label, active: convDest == raw) { convDest = raw }
    }

    private func settingChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        SettingChip(label, active: active, action: action)
    }

    private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            convDestPath = url.path
            convDest = "custom"
        }
    }

    // MARK: - Keep awake

    private var keepAwakeSection: some View {
        let awake = model.keepAwake
        return VStack(spacing: 12) {
            HStack(spacing: 6) {
                // moon + status = the toggle itself: off ↔ ∞, clicking the time turns it off
                Button {
                    if awake.isActive {
                        awake.deactivate()
                    } else if let longest = KeepAwakeController.options.last {
                        awake.activate(longest) // ∞
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: awake.isActive ? "moon.fill" : "moon")
                            .font(.system(size: 12))
                        Text(awake.isActive ? awakeRemaining : t(.awakeOff))
                            .font(Theme.mono(awakeRemaining == "∞" && awake.isActive ? 16 : 11,
                                             weight: awakeRemaining == "∞" && awake.isActive
                                                 ? .medium
                                                 : (awake.isActive ? .semibold : .medium)))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(awake.isActive ? Theme.editing : Theme.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    ForEach(KeepAwakeController.options, id: \.label) { option in
                        awakeChip(option)
                    }
                }
                // lid — a permanent slot at the end of the row: nothing jumps around.
                // with the module off, a click enables ∞ and the lid right away
                Button {
                    awake.toggleLid() // independent of the moon and the timers
                } label: {
                    // same shape always: only color shows activity
                    lidGlyph(
                        closed: false,
                        color: awake.lidApplied
                            ? Theme.editing
                            : (awake.isActive ? Theme.textSecondary : Theme.textTertiary)
                    )
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(4)
                .help(t(.awakeLid))
                .padding(.leading, 1)
            }
        }
    }

    /// Side-view laptop per Anton's reference (2026-07-13): the screen tilted
    /// left of vertical, the base extending right of the hinge, inside — an arc
    /// arrow falling down toward the base (lid-closing gesture).
    private func lidGlyph(closed: Bool, color: Color) -> some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let stroke = StrokeStyle(lineWidth: 1.4, lineCap: .round)
            let baseY = h * 0.82
            if closed {
                // closed: a flat laptop — base and lid pressed together
                var base = Path()
                base.move(to: CGPoint(x: 2, y: baseY))
                base.addLine(to: CGPoint(x: w - 2, y: baseY))
                ctx.stroke(base, with: .color(color), style: stroke)
                var lid = Path()
                lid.move(to: CGPoint(x: 2, y: baseY - 3.2))
                lid.addLine(to: CGPoint(x: w - 2, y: baseY - 3.2))
                ctx.stroke(lid, with: .color(color), style: stroke)
                return
            }
            // hinge at a third of the width, the base extends to the right
            let hinge = CGPoint(x: w * 0.24, y: baseY)
            var base = Path()
            base.move(to: hinge)
            base.addLine(to: CGPoint(x: w - 1.5, y: baseY))
            ctx.stroke(base, with: .color(color), style: stroke)
            // screen: tilted ~18° left of vertical, nearly full height
            let screenLength = baseY - 1.5
            let top = CGPoint(x: hinge.x - screenLength * 0.31,
                              y: hinge.y - screenLength * 0.95)
            var screen = Path()
            screen.move(to: hinge)
            screen.addLine(to: top)
            ctx.stroke(screen, with: .color(color), style: stroke)
            // closing arc: from the top of the screen rightward and down to the base
            let arcStart = CGPoint(x: w * 0.38, y: h * 0.18)
            let arcEnd = CGPoint(x: w * 0.76, y: h * 0.60)
            let control = CGPoint(x: w * 0.82, y: h * 0.16)
            var arc = Path()
            arc.move(to: arcStart)
            arc.addQuadCurve(to: arcEnd, control: control)
            ctx.stroke(arc, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            // chevron arrowhead pointing down, as in the reference
            var head = Path()
            head.move(to: CGPoint(x: arcEnd.x - 2.6, y: arcEnd.y - 2.4))
            head.addLine(to: arcEnd)
            head.addLine(to: CGPoint(x: arcEnd.x + 2.6, y: arcEnd.y - 2.4))
            ctx.stroke(head, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 20, height: 14)
    }

    /// Inline awake options: keep the display on / run with the lid closed.
    private func awakeOptionIcon(
        _ symbol: String, isOn: Bool, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isOn ? Theme.editing : Theme.textTertiary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(4)
        .help(help)
    }

    private var awakeRemaining: String {
        guard model.keepAwake.isActive else { return "" }
        guard let remaining = model.keepAwake.remaining else { return "∞" }
        // compact, no seconds: 29m / 1h59m — unit letters are localized
        let minutes = max(1, Int((remaining / 60).rounded(.up)))
        if minutes >= 60 {
            return "\(minutes / 60)\(t(.unitHour))\(String(format: "%02d", minutes % 60))\(t(.unitMin))"
        }
        return "\(minutes)\(t(.unitMin))"
    }

    /// No-sleep option label: minutes as a bare number, hours with the
    /// localized hour letter (1h in each language), infinity as the symbol.
    private func awakeOptionLabel(_ option: KeepAwakeController.Option) -> String {
        guard let seconds = option.seconds else { return "∞" }
        if seconds >= 3600 { return "\(Int(seconds) / 3600)\(t(.unitHour))" }
        return "\(Int(seconds) / 60)"
    }

    private func awakeChip(_ option: KeepAwakeController.Option) -> some View {
        let isActive = model.keepAwake.isActive && model.keepAwake.selected == option
        let isInfinity = option.seconds == nil
        return Button {
            model.keepAwake.toggle(option)
        } label: {
            Text(awakeOptionLabel(option))
                .font(Theme.mono(isInfinity ? 15 : 11, weight: .medium)) // activity shown by color, not weight
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                // the mono font's ∞ sits below the optical center — nudge it up
                .offset(y: isInfinity ? -1 : 0)
                .frame(minWidth: 18)
                .padding(.horizontal, 3)
                .frame(height: 22) // glyph centered in the frame
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isActive ? Theme.controlStroke : .clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Settings

    private var settingsScreen: some View {
        VStack(spacing: 16) {
            SectionChips(items: [
                ("general", t(.aboutTabGeneral)),
                ("timer", t(.aboutTabTimer)),
                ("modules", t(.otherModulesLabel)),
                ("monitor", t(.tabSystem)),
            ], selection: $settingsSection)

            switch settingsSection {
            case "timer":
                timerSettings
            case "monitor":
                thresholdsSection
            case "modules":
                modulesSettings
            default:
                generalSettings
            }
        }
        .padding(.vertical, 4)
    }


    private static let moduleRowHeight: CGFloat = 30

    /// One row of the settings module list: either a tab header (icon + "#N",
    /// not draggable) or a module row. All rows share `moduleRowHeight`, so a
    /// pixel offset maps to a whole number of rows and the drag math stays
    /// uniform whether it steps over a header or a module.
    private enum ModuleListRow: Identifiable {
        case header(tab: PanelTab, number: Int)
        case module(key: String)

        var id: String {
            switch self {
            case .header(let tab, _): return "h-\(tab.id.uuidString)"
            case .module(let key): return "m-\(key)"
            }
        }

        func isModule(_ key: String) -> Bool {
            if case .module(let k) = self { return k == key }
            return false
        }
    }

    /// The module list grouped by tab: each tab contributes a header followed
    /// by its module rows. Every module key is listed, so the settings rows
    /// match the spaces' moduleKeys one-to-one.
    private var moduleListRows: [ModuleListRow] {
        var rows: [ModuleListRow] = []
        for (index, tab) in tabsModel.tabs.enumerated() {
            rows.append(.header(tab: tab, number: index + 1))
            for key in tab.moduleKeys {
                rows.append(.module(key: key))
            }
        }
        return rows
    }

    @ViewBuilder private func moduleListRowView(_ row: ModuleListRow, index: Int) -> some View {
        switch row {
        case .header(let tab, let number):
            moduleHeaderRow(tab: tab, number: number, index: index)
        case .module(let key):
            draggableModuleRow(key, index: index)
        }
    }

    /// Tab header: the tab's icon and its 1-based position, tertiary. It slides
    /// with the reorder gap like any row, but carries no drag gesture or toggle.
    private func moduleHeaderRow(tab: PanelTab, number: Int, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: tab.icon)
                .font(.system(size: 11))
                .frame(width: 14, alignment: .leading)
            Text("#\(number)")
                .font(Theme.mono(11))
            Spacer()
        }
        .foregroundStyle(Theme.textTertiary)
        .padding(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 2))
        .frame(height: Self.moduleRowHeight)
        .offset(y: moduleRowShift(index))
        .animation(.easeInOut(duration: 0.15), value: moduleRowShift(index))
    }

    /// Module row wired for reordering: fixed height (drag math relies on
    /// it), neighbors shift out of the way live, the dragged row tracks the
    /// pointer without animation so it never lags behind the hand.
    private func draggableModuleRow(_ key: String, index: Int) -> some View {
        let isDragged = dragModuleKey == key
        return moduleRow(key)
            .padding(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 2))
            .frame(height: Self.moduleRowHeight)
            .contentShape(Rectangle())
            .opacity(isDragged ? 0.4 : 1)
            .offset(y: isDragged ? dragModuleOffset : moduleRowShift(index))
            .zIndex(isDragged ? 1 : 0)
            .animation(isDragged ? nil : .easeInOut(duration: 0.15),
                       value: moduleRowShift(index))
            .gesture(moduleDragGesture(key))
    }

    /// Display index of the module currently being dragged, or nil.
    private func draggedModuleIndex() -> Int? {
        guard let key = dragModuleKey else { return nil }
        return moduleListRows.firstIndex { $0.isModule(key) }
    }

    /// How far a resting row steps aside to open a gap at the drop target.
    /// `index` is the display index across the flat header+module list.
    private func moduleRowShift(_ index: Int) -> CGFloat {
        guard let from = draggedModuleIndex(),
              let target = dragModuleTarget, index != from else { return 0 }
        if from < index, target >= index { return -Self.moduleRowHeight }
        if from > index, target <= index { return Self.moduleRowHeight }
        return 0
    }

    private func moduleDragGesture(_ key: String) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let rows = moduleListRows
                guard let from = rows.firstIndex(where: { $0.isModule(key) }) else { return }
                if dragModuleKey == nil {
                    dragModuleKey = key
                    dragModuleTarget = from
                }
                dragModuleOffset = value.translation.height
                let steps = Int((value.translation.height / Self.moduleRowHeight).rounded())
                // index 0 is always tab 1's header — never a valid drop slot, so
                // clamp the low end to 1 ("position 0 of tab 1"), not 0.
                let target = min(max(from + steps, 1), rows.count - 1)
                if target != dragModuleTarget {
                    dragModuleTarget = target
                    Sounds.scrubTick()
                }
            }
            .onEnded { _ in
                let rows = moduleListRows
                // the visual offset nearly equals the committed displacement,
                // so the settle is a short glide, not a jump
                withAnimation(.easeInOut(duration: 0.15)) {
                    if let from = rows.firstIndex(where: { $0.isModule(key) }),
                       let target = dragModuleTarget, target != from {
                        applyModuleDrop(key: key, from: from, to: target, rows: rows)
                    }
                    dragModuleKey = nil
                    dragModuleTarget = nil
                    dragModuleOffset = 0
                }
            }
    }

    /// Translates a display-list drop (module `key` from display index `from` to
    /// `to`) into a `(tab, position)` move on the tabs model. The module's new
    /// tab is the nearest header above its landing slot; its position is the
    /// count of module rows between that header and the slot. `move` re-homes it,
    /// `reorder` places it — a same-tab drop collapses to a plain reorder.
    private func applyModuleDrop(key: String, from: Int, to: Int, rows: [ModuleListRow]) {
        var arranged = rows
        arranged.insert(arranged.remove(at: from), at: to)
        guard let landed = arranged.firstIndex(where: { $0.isModule(key) }) else { return }
        var destTab: UUID?
        var position = 0
        var i = landed - 1
        while i >= 0 {
            if case .header(let tab, _) = arranged[i] { destTab = tab.id; break }
            position += 1
            i -= 1
        }
        guard let destTab else { return }
        mutateTabs {
            $0.move(module: key, toTab: destTab)
            $0.reorder(module: key, inTab: destTab, to: position)
        }
    }

    /// Module row: burger handle (drag anywhere on the row), name, toggle.
    private func moduleRow(_ key: String) -> some View {
        HStack(spacing: 10) {
            // drag handle: two lines, left-aligned
            VStack(alignment: .leading, spacing: 3) {
                Capsule().frame(width: 11, height: 1.5)
                Capsule().frame(width: 11, height: 1.5)
            }
            .foregroundStyle(Theme.textTertiary)
            .frame(width: 14, height: 18, alignment: .leading)
            Text(moduleTitle(key))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Theme.MiniSwitch(isOn: moduleBinding(key))
        }
    }

    private var generalSettings: some View {
        VStack(spacing: 14) {
            HStack {
                Text(t(.themeLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                themeIcon("auto", "circle.lefthalf.filled", t(.themeAuto))
                themeIcon("dark", "moon", t(.themeDark))
                themeIcon("light", "sun.max", t(.themeLight))
            }


            HStack {
                Text(t(.language))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                languageDropdown
            }

            HStack {
                Text(t(.launchAtLogin))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Theme.MiniSwitch(isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        setLaunchAtLogin(on)
                    }
            }
            .onAppear {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }

            soundsSettings

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            // updates right after the basics (Anton, 2026-07-14): version and
            // the update button matter more often than module reordering
            updatesSection

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            // Finder icon lives away from the theme row on purpose: right
            // under it the two pickers read as one confusing "theme" block
            HStack {
                Text(t(.appIconLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                appIconChip(dark: false)
                appIconChip(dark: true)
            }

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            // tabs (spaces) management — the only place to add/reorder/rename/
            // delete spaces, so a stray header click can no longer spawn one.
            VStack(spacing: 12) {
                settingsSectionHeader(t(.tabsSettingsTitle))
                // separate stack from the module list below: the two hand-rolled
                // drags keep separate state so they never fight.
                VStack(spacing: 0) {
                    ForEach(Array(tabsModel.tabs.enumerated()), id: \.element.id) { index, tab in
                        tabSettingsRow(tab, index: index)
                    }
                    if tabsModel.tabs.count < PanelTabsModel.maxTabs {
                        addTabRow
                    }
                }
            }

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            VStack(spacing: 12) {
                HStack {
                    Text(t(.modulesLabel))
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
                // hand-rolled drag reorder instead of List.onMove: the system
                // drop indicator draws a dot that clips at our insets and can't
                // be removed. Rows part to make a gap; the dragged row follows
                // the pointer semi-transparent. Plain VStack also renders in
                // snapshots, where List (NSTableView) doesn't.
                VStack(spacing: 0) {
                    ForEach(Array(moduleListRows.enumerated()), id: \.element.id) { index, row in
                        moduleListRowView(row, index: index)
                    }
                }
            }

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            hotkeysSection
        }
    }

    private var timerSettings: some View {
        VStack(spacing: 14) {
            HStack {
                Text(t(.menuBarCountdown))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Theme.MiniSwitch(isOn: $showCountdown)
            }

            HStack {
                Text(t(.trackerBarTime))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Theme.MiniSwitch(isOn: $trackerTimeInBar)
            }

            HStack {
                Text(t(.onFinish))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                ForEach(AlertMode.allCases) { mode in
                    alertModeButton(mode)
                }
            }

            HStack {
                Text(t(.pauseMediaLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                    .help(t(.pauseMediaHint))
                Spacer()
                Theme.MiniSwitch(isOn: $pauseMedia)
            }

            HStack {
                Text(t(.timerStyle))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                styleChip(t(.styleCompact), compact: true)
                styleChip(t(.styleLarge), compact: false)
            }

            HStack {
                Text(t(.displayStyleLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                displayStyleCard("dots", t(.styleDots))
                displayStyleCard("text", t(.styleText))
                displayStyleCard("units", t(.styleUnits))
            }
            HStack {
                Text(t(.digitsSizeLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                // chips sized like the "timer size" ones — paired settings stay uniform
                bigToggleChip(t(.digitsLargeLabel), active: digitsSize == "large") { digitsSize = "large" }
                bigToggleChip(t(.digitsSmallLabel), active: digitsSize == "small") { digitsSize = "small" }
            }

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            presetsEditor

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            cyclesEditor
        }
    }

    /// Keep-awake, clipboard, converter and windows have few settings —
    /// they live as sections on a single tab.
    private var modulesSettings: some View {
        VStack(spacing: 14) {
            VStack(spacing: 14) {
                settingsSectionHeader(t(.awakeOff))
                awakeSettings
            }
            Rectangle().fill(Theme.divider).frame(height: 1)
            VStack(spacing: 14) {
                settingsSectionHeader(t(.tabClipboard))
                clipboardSettings
            }
            Rectangle().fill(Theme.divider).frame(height: 1)
            VStack(spacing: 14) {
                settingsSectionHeader(t(.convertLabel))
                converterSettings
            }
            Rectangle().fill(Theme.divider).frame(height: 1)
            VStack(spacing: 14) {
                settingsSectionHeader(t(.windowsLabel))
                HStack {
                    Text(t(.windowsLayoutLabel))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    settingChip(t(.windowsGrid), active: windowsLayout == "grid") { windowsLayout = "grid" }
                    settingChip(t(.windowsRow), active: windowsLayout == "row") { windowsLayout = "row" }
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(t(.windowsHotkeysLabel))
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Theme.MiniSwitch(isOn: $windowsHotkeysOn)
                    }
                    // zone glyph + its combo, same pairs as the help legend
                    // four columns: 18 zones in two-column form wasted half
                    // the width and stretched the section (Anton, 2026-07-15)
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), alignment: .leading),
                            count: 4
                        ),
                        alignment: .leading, spacing: 7
                    ) {
                        ForEach(Self.snapHotkeyItems, id: \.0) { position, key in
                            HStack(spacing: 8) {
                                snapGlyph(position)
                                    .frame(width: 22, height: 14)
                                Text("⌃ ⌥ \(key)")
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.textTertiary)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .onChange(of: windowsHotkeysOn) {
                    HotkeyManager.shared.refreshSnapHotkeys()
                }
            }
            Rectangle().fill(Theme.divider).frame(height: 1)
            VStack(spacing: 14) {
                settingsSectionHeader(t(.torrentLabel))
                torrentSettings
            }
        }
    }

    private var torrentSettings: some View {
        VStack(spacing: 14) {
            HStack {
                Text(t(.torrentFolderLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                settingChip(t(.convDestDownloads), active: torrentDownloadDir.isEmpty) {
                    torrentDownloadDir = ""
                }
                Button {
                    chooseTorrentFolder()
                } label: {
                    Text(torrentDownloadDir.isEmpty
                        ? "…"
                        : URL(fileURLWithPath: torrentDownloadDir).lastPathComponent)
                        .font(Theme.mono(10))
                        .foregroundStyle(torrentDownloadDir.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            torrentDownloadDir.isEmpty ? .clear : Theme.chipBg,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(torrentDownloadDir.isEmpty ? Theme.divider : Theme.controlStroke, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(5)
            }

            HStack {
                Text(t(.torrentStopRatio))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Theme.MiniSwitch(isOn: $torrentStopAtRatio1)
            }

            // blank / 0 = unlimited; NumericField caps at three digits (KB/s)
            HStack {
                Text(t(.torrentRateLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                NumericField(value: $torrentRateDown, range: 0...999)
                Image(systemName: "arrow.up")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                NumericField(value: $torrentRateUp, range: 0...999)
            }

            HStack {
                Text(t(.torrentShowWhenEmpty))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Theme.MiniSwitch(isOn: $torrentShowWhenEmpty)
            }

            // An offer, never automatic on install: register Hop as the system
            // handler for .torrent files so a double-click opens the add flow.
            Button {
                makeHopDefaultForTorrent()
            } label: {
                HStack {
                    Text(t(.torrentMakeDefault))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .hoverHighlight(7)
        }
    }

    /// Register this bundle as the default handler for `.torrent` documents AND
    /// `magnet:` links. The dev build carries its own bundle id, so it claims the
    /// defaults for itself — the production Hop is left alone. Once Hop owns the
    /// type, Finder shows Hop's document icon (Info.plist CFBundleTypeIconFile)
    /// instead of the previous client's.
    private func makeHopDefaultForTorrent() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.antonshakirov.minimo"
        LSSetDefaultRoleHandlerForContentType(
            "org.bittorrent.torrent" as CFString, .all, bundleID as CFString)
        LSSetDefaultHandlerForURLScheme("magnet" as CFString, bundleID as CFString)
    }

    private func chooseTorrentFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            torrentDownloadDir = url.path
        }
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.mono(10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
    }

    private var awakeSettings: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(t(.awakeKeepDisplay))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Theme.MiniSwitch(isOn: $awakeKeepDisplay)
                        .onChange(of: awakeKeepDisplay) { _, _ in
                            model.keepAwake.refreshForSettingsChange()
                        }
                }
                Text(t(.awakeKeepDisplayNote))
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
    }

    private var clipboardSettings: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(t(.clipboardLimit))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    NumericField(value: $clipboardMax, range: 5...300)
                }
                Text(t(.clipboardLimitNote))
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.textTertiary)
            }
            HStack {
                Text(t(.clipVisibleRows))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                NumericField(value: $clipboardVisibleRows, range: 1...10)
            }
        }
    }

    private var hotkeysSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text(t(.hotkeysLabel))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            hotkeyRow(.panel, label: t(.hkPanel))
            hotkeyRow(.timer, label: t(.hkTimer))
            hotkeyRow(.awake, label: t(.hkAwake))
        }
    }

    private func hotkeyRow(_ action: HotkeyManager.Action, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    startRecording(action)
                } label: {
                    Text(recordingHotkey == action ? t(.hkRecord) : hotkeys.combo(for: action).display)
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(recordingHotkey == action ? Theme.editing : Theme.textPrimary)
                        .frame(minWidth: 64)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(5)
            }
            if hotkeys.conflicts.contains(action) {
                Text(t(.hkTaken))
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.accentRed)
            }
        }
    }

    /// Recorder: the next keypress with modifiers becomes the combo.
    private func startRecording(_ action: HotkeyManager.Action) {
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
        recordingHotkey = action
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer {
                if let monitor = hotkeyMonitor {
                    NSEvent.removeMonitor(monitor)
                    hotkeyMonitor = nil
                }
                recordingHotkey = nil
            }
            if event.keyCode == UInt16(kVK_Escape) {
                return nil // cancel recording
            }
            if let combo = HotkeyManager.Combo(event: event) {
                hotkeys.setCombo(combo, for: action)
                return nil
            }
            return nil
        }
    }

    private var soundsSettings: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(t(.muteAllLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Theme.MiniSwitch(isOn: $appSoundsOn)
            }
            Text(t(.muteAllNote))
                .font(Theme.mono(8))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Time presets

    private var presetsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t(.presetsLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Theme.MiniSwitch(isOn: $showPresetsRow)
            }
            HStack(spacing: 6) {
                NumericField(value: $newPresetMinutes, range: 1...999)
                Button {
                    addPreset(newPresetMinutes)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.divider, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(4)
                Spacer()
            }
            // chips wrap onto new lines — digits never get squeezed
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 56), spacing: 6, alignment: .leading)],
                alignment: .leading, spacing: 6
            ) {
                ForEach(presets, id: \.self) { minutes in
                    Button {
                        removePreset(minutes)
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(minutes)")
                                .font(Theme.mono(11, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .fixedSize()
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.divider, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cyclesEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t(.cycleTemplatesLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Theme.MiniSwitch(isOn: $showCyclesRow)
            }
            HStack(spacing: 6) {
                Text(t(.workLabel))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                NumericField(value: $newCycleWork, range: 1...180)
                Text(t(.restLabel))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                NumericField(value: $newCycleRest, range: 0...60)
                Text("×")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                NumericField(value: $newCycleRounds, range: 1...12)
                Button {
                    addCycleTemplate()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.divider, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(4)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 84), spacing: 6, alignment: .leading)],
                alignment: .leading, spacing: 6
            ) {
                ForEach(Array(cycleTemplates.enumerated()), id: \.offset) { index, template in
                    Button {
                        removeCycleTemplate(at: index)
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(template.work)/\(template.rest)×\(template.rounds)")
                                .font(Theme.mono(11, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .fixedSize()
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.divider, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addCycleTemplate() {
        guard cycleTemplates.count < 6 else { return }
        var list = cycleTemplates
        list.append((newCycleWork, newCycleRest, newCycleRounds))
        // ascending by work duration — the usual sort for such presets
        list.sort { ($0.work, $0.rest, $0.rounds) < ($1.work, $1.rest, $1.rounds) }
        cycleTemplatesRaw = list.map { "\($0.work)/\($0.rest)x\($0.rounds)" }.joined(separator: ",")
    }

    private func removeCycleTemplate(at index: Int) {
        var list = cycleTemplates
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        cycleTemplatesRaw = list.map { "\($0.work)/\($0.rest)x\($0.rounds)" }.joined(separator: ",")
    }

    private func removePreset(_ minutes: Int) {
        presetsRaw = presets.filter { $0 != minutes }
            .map(String.init).joined(separator: ",")
    }

    private func addPreset(_ minutes: Int) {
        guard presets.count < 8 else { return }
        presetsRaw = Array(Set(presets + [minutes])).sorted()
            .map(String.init).joined(separator: ",")
    }

    // MARK: - Updates

    private var updatesSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(t(.updatesLabel))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            HStack {
                Text(t(.autoUpdateLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Theme.MiniSwitch(isOn: $autoUpdateOn)
            }
            // version next to the update button: it is clear WHAT you are updating
            HStack(spacing: 8) {
                Button {
                    Task { await model.updater.check(manual: true) }
                } label: {
                    Text(t(.checkUpdates))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.divider, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(5)
                Text("\(t(.versionLabel)) \(model.updater.currentVersion)")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(updateStatusText)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var updateStatusText: String {
        switch model.updater.status {
        case .idle: return ""
        case .checking: return "…"
        case .upToDate: return t(.upToDate)
        case .downloading: return t(.updDownloading)
        case .installing: return t(.updInstalling)
        case .failed: return t(.updFailed)
        }
    }


    // MARK: - System highlight thresholds

    private var thresholdsSection: some View {
        VStack(spacing: 12) {

            HStack {
                Text(t(.monitorColorLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Theme.MiniSwitch(isOn: $monitorColorful)
            }
            HStack {
                Text(t(.monitorDetailedLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Theme.MiniSwitch(isOn: $monitorDetailed)
            }
            HStack {
                Text(t(.monitorWindowLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                // one hour is the ceiling: the buffer holds 61 minutes, memory cost is trivial
                ForEach([5, 10, 30, 60], id: \.self) { minutes in
                    settingChip(
                        minutes == 60 ? "1\(t(.unitHour))" : "\(minutes)\(t(.unitMin))",
                        active: monitorWindowMin == minutes
                    ) {
                        monitorWindowMin = minutes
                    }
                }
                .onAppear {
                    // migration from the old 1-minute option
                    if monitorWindowMin == 1 { monitorWindowMin = 5 }
                }
            }
            HStack {
                Text(t(.redAlertLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Theme.MiniSwitch(isOn: $menuBarRedAlert)
            }

            HStack {
                Text(t(.tempUnitLabel))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                unitChip("auto", label: t(.languageAuto))
                unitChip("c", label: "°C")
                unitChip("f", label: "°F")
            }

            // free input, digits only; red is always stricter than yellow
            HStack {
                Text(t(.thGeneralNote))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            .padding(.top, 2)
            ThresholdRow(label: t(.thTemp), yellow: $tempYellow, red: $tempRed, maxValue: 130)
            ThresholdRow(label: t(.thLoad), yellow: $loadYellow, red: $loadRed, maxValue: 100)
            ThresholdRow(label: t(.thDisk), yellow: $diskYellow, red: $diskRed, maxValue: 100)
            VStack(alignment: .leading, spacing: 3) {
                // battery is inverted: lower = worse, hence red < yellow
                ThresholdRow(label: t(.thBatt), yellow: $battYellow, red: $battRed,
                             maxValue: 100, inverted: true)
                Text(t(.thBattNote))
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.textTertiary)
            }

            // memory has no threshold row on purpose: its color follows
            // macOS's own memory-pressure signal, and the caption says so
            HStack {
                Text(t(.memPressureNote))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }

            HStack {
                Spacer()
                Button {
                    tempYellow = Thresholds.tempYellowDefault
                    tempRed = Thresholds.tempRedDefault
                    loadYellow = Thresholds.loadYellowDefault
                    loadRed = Thresholds.loadRedDefault
                    diskYellow = Thresholds.diskYellowDefault
                    diskRed = Thresholds.diskRedDefault
                    battYellow = Thresholds.battYellowDefault
                    battRed = Thresholds.battRedDefault
                } label: {
                    Text(t(.resetThresholds))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Theme.divider, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(5)
            }
        }
    }

    // MARK: - About

    /// Icon legend for the current help tab: what it is and what it does.
    private var aboutIconLegend: [(String, String)]? {
        switch aboutSection {
        case "timer":
            return [
                ("play.fill", t(.hkTimer)),
                ("arrow.counterclockwise", t(.iconReset)),
                ("stopwatch", t(.stopwatchLabel)),
                ("arrow.uturn.backward", t(.iconPocket)),
            ]
        case "awake":
            return [
                ("moon", t(.awakeOff)),
                ("lid", t(.awakeLid)),
            ]
        case "more":
            return [
                ("doc.on.doc", t(.iconCopy)),
                ("text.insert", t(.iconPaste)),
                ("arrow.up.left.and.arrow.down.right", t(.iconExpand)),
            ]
        case "general":
            return [
                ("gearshape", t(.settingsTitle)),
                ("power", t(.menuQuit)),
                ("info.circle", t(.aboutTitle)),
            ]
        case "convert":
            return [
                ("arrow.up.forward.app", t(.convertLabel)),
                ("arrow.down.doc", t(.convDrop)),
            ]
        default:
            return nil
        }
    }

    /// Zone → key pairs, shared by the help legend and the settings section.
    /// Every zone of the scheme is listed — a hidden hotkey is a lost hotkey.
    static let snapHotkeyItems: [(WindowSnapController.Position, String)] = [
        (.leftHalf, "←"), (.rightHalf, "→"),
        (.topHalf, "↑"), (.bottomHalf, "↓"),
        (.maximize, "↩"), (.center, "C"),
        (.topLeft, "U"), (.topRight, "I"),
        (.bottomLeft, "J"), (.bottomRight, "K"),
        (.leftThird, "D"), (.centerThird, "F"),
        (.rightThird, "G"), (.leftTwoThirds, "E"),
        (.rightTwoThirds, "T"), (.centerHalf, "S"),
        (.topThird, "O"), (.bottomThird, "L"),
    ]

    /// Windows hotkey legend: zone glyph + combo (⌃ ⌥ …), in four columns.
    private var windowsHotkeyLegend: some View {
        let items = Self.snapHotkeyItems
        return VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
            Text(t(.hotkeysLabel))
                .font(Theme.mono(10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), alignment: .leading),
                    count: 4
                ),
                alignment: .leading, spacing: 9
            ) {
                ForEach(items, id: \.0) { position, key in
                    HStack(spacing: 10) {
                        snapGlyph(position)
                            .frame(width: 26, height: 17)
                        Text("⌃ ⌥ \(key)")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder private func legendIcon(_ name: String) -> some View {
        if name == "lid" {
            lidGlyph(closed: false, color: Theme.textSecondary)
                .frame(width: 22, alignment: .center)
        } else {
            Image(systemName: name)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22)
        }
    }

    private var settingsTabLabels: [String] {
        [t(.aboutTabGeneral), t(.aboutTabTimer), t(.otherModulesLabel), t(.tabSystem)]
    }

    private var aboutTabLabels: [String] {
        [t(.aboutTabGeneral), t(.aboutTabTimer), t(.awakeOff),
         t(.tabSystem), t(.tabClipboard), t(.convertLabel), t(.windowsLabel),
         t(.speedtestLabel)]
    }

    private var aboutScreen: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionChips(items: [
                ("general", t(.aboutTabGeneral)),
                ("timer", t(.aboutTabTimer)),
                ("awake", t(.awakeOff)),
                ("monitor", t(.tabSystem)),
                ("more", t(.tabClipboard)),
                ("convert", t(.convertLabel)),
                ("windows", t(.windowsLabel)),
                ("speed", t(.speedtestLabel)),
                ("news", t(.aboutTabNews)),
            ], selection: $aboutSection, wraps: true)

            Group {
                switch aboutSection {
                case "timer":
                    DocView(text: t(.docTimerFull))
                case "monitor":
                    VStack(alignment: .leading, spacing: 10) {
                        DocView(text: t(.docMonitorRows))
                        DocView(text: t(.docMonitorRows2))
                        DocView(text: t(.docMonitorColors))
                    }
                case "awake":
                    DocView(text: t(.docAwakeFull))
                case "more":
                    DocView(text: t(.docClipboardFull))
                case "convert":
                    DocView(text: t(.docConverterFull))
                case "windows":
                    DocView(text: t(.docWindowsFull))
                    windowsHotkeyLegend
                case "speed":
                    DocView(text: t(.docSpeedFull))
                case "news":
                    // last ~5 releases, 2-4 bullets each (older ones drop off);
                    // the full history lives on GitHub Releases
                    VStack(alignment: .leading, spacing: 10) {
                        DocView(text: t(.docNews))
                        FooterLink(url: "https://github.com/antonyshakirov/hop/releases",
                                   label: t(.newsAllReleases))
                    }
                default:
                    DocView(text: t(.docGeneral))
                }
            }

            if let legend = aboutIconLegend {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(legend.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 10) {
                            legendIcon(item.0)
                            Text(item.1)
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.docText)
                        }
                    }
                }
            }

            if aboutSection == "general" {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                        Text("open source · \(t(.versionLabel)) \(model.updater.currentVersion) ·")
                            .foregroundStyle(Theme.textSecondary)
                        FooterLink(url: "https://github.com/antonyshakirov/hop", label: "GitHub")
                    }
                    HStack(spacing: 6) {
                        Text("\(t(.aboutFooter)) ·")
                            .foregroundStyle(Theme.textSecondary)
                        FooterLink(url: lang == .ru
                            ? "https://antonshakirov.com"
                            : "https://antonshakirov.com/en")
                        Text("·")
                            .foregroundStyle(Theme.textSecondary)
                        // landing exists in 8 languages; everyone else gets English
                        FooterLink(url: productPageURL, label: t(.aboutProductPage))
                    }
                }
            }
        }
        .font(Theme.mono(12))
        .foregroundStyle(Theme.textPrimary)
        .lineSpacing(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }


    /// Chip sized like the "timer size" one — for paired toggle settings.
    private func bigToggleChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.mono(10))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(
                    active ? Theme.chipBg : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(active ? Theme.controlStroke : Theme.divider, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
    }

    private func styleChip(_ label: String, compact: Bool) -> some View {
        let active = timerCompact == compact
        return Button {
            timerCompact = compact
        } label: {
            Text(label)
                .font(Theme.mono(10))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(
                    active ? Theme.chipBg : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(active ? Theme.controlStroke : Theme.divider, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Mini display-format card: a live sample inside, the label as a tooltip.
    private func displayStyleCard(_ raw: String, _ label: String) -> some View {
        SettingChip(active: displayStyle == raw, action: { displayStyle = raw }) {
            Group {
                // visual digit height roughly equal across all three samples
                switch raw {
                case "text":
                    Text("12:34")
                        .font(Theme.mono(17, weight: .semibold))
                        .monospacedDigit()
                case "units":
                    Text("12\(t(.unitMin)) 34\(t(.unitSec))")
                        .font(Theme.mono(17, weight: .semibold))
                        .monospacedDigit()
                default:
                    DotMatrixDisplay(text: "12:34", dimCount: 0, blinkOff: false, cell: 2.0)
                }
            }
            .frame(height: 18)
        }
        .help(label)
    }

    /// Theme — three icons: auto (half circle), moon, sun.
    private func themeIcon(_ raw: String, _ symbol: String, _ label: String) -> some View {
        SettingChip(active: themeRaw == raw, action: {
            themeRaw = raw
            model.refreshTheme?()
        }) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(minWidth: 15)
        }
        .help(label)
    }

    private func unitChip(_ raw: String, label: String) -> some View {
        SettingChip(label, active: tempUnitRaw == raw) { tempUnitRaw = raw }
    }

    /// Language picker: native dropdown menu, no background plate;
    /// the arrow stays on the right and never moves.
    private var languageDropdown: some View {
        LanguagePicker(selection: $languageRaw)
    }

    private func appIconChip(dark: Bool) -> some View {
        let active = (appIconStyle == "dark") == dark
        return Button {
            appIconStyle = dark ? "dark" : "light"
            AppIcon.apply()
        } label: {
            // the two REAL icons as the choices — clearer than words
            Image(nsImage: AppIcon.preview(dark: dark))
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(active ? Theme.textPrimary : Theme.divider, lineWidth: active ? 1.5 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
    }

    private func alertModeButton(_ mode: AlertMode) -> some View {
        SettingChip(active: alertModeRaw == mode.rawValue, action: {
            alertModeRaw = mode.rawValue
            if mode == .soundAndBanner {
                Alerts.requestPermissionIfPossible()
            }
        }) {
            Image(systemName: mode.icon)
                .font(.system(size: 13))
                .frame(minWidth: 15)
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let service = SMAppService.mainApp
        do {
            if on, service.status != .enabled { try service.register() }
            if !on, service.status == .enabled { try service.unregister() }
        } catch {
            // failed — show the actual state
            launchAtLogin = service.status == .enabled
        }
    }

}
