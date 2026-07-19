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
    // A tracker inline field (project/task name or "today" time) is focused.
    // Feeds `panelKeyboardCaptured` alongside `editUnit` so `handleKey` lets
    // Return/Space/digits reach the field instead of driving the timer.
    @State private var trackerEditing = false
    // A to-do inline field is focused — same keyboard-capture concern as the
    // tracker's fields (digits must not leak to the timer sharing this space).
    @State private var todosEditing = false
    @State private var languageMenuTarget: MenuPickTarget?
    // Settings module table (a column per tab + a permanent inactive column):
    // one hand-rolled drag moves a module chip between/within columns; a header
    // drag reorders whole tab columns. Column and chip frames are measured in
    // the "modTable" coordinate space so a drop resolves to a column + index.
    @State private var dragChip: String?                 // module key being dragged
    @State private var dragChipTranslation: CGSize = .zero
    @State private var dropColumn: String?               // highlighted target: "inactive" or a tab uuid
    @State private var columnFrames: [String: CGRect] = [:]
    @State private var chipFrames: [String: CGRect] = [:]
    @State private var dragHeaderTab: UUID?              // tab column being header-dragged
    @State private var dragHeaderTranslation: CGFloat = 0
    @State private var confirmDeleteTab: UUID?          // inline delete confirmation target
    // non-nil while the icon picker grid is open for that tab column
    @State private var iconPickerTabID: UUID?
    // which tab column header is hovered — its delete xmark shows only then
    // (same reveal-on-hover pattern as the tracker/torrent row deletes)
    @State private var hoveredTabRow: UUID?
    @AppStorage("cycleTemplates") private var cycleTemplatesRaw = "25/5x4,52/17x3,90/15x2"
    @AppStorage("showPresetsRow") private var showPresetsRow = true
    @AppStorage("showCyclesRow") private var showCyclesRow = true
    // Per-module visibility is membership now (the inactive bucket in the tabs
    // model), not `show*Module` toggles — those legacy keys are read once by
    // `migrateModuleVisibility` and never again.
    @AppStorage(FileConverter.formatKey) private var convFormat = "jpeg"
    @AppStorage(FileConverter.scaleKey) private var convScale = 1.0
    @AppStorage(FileConverter.qualityKey) private var convQuality = 55
    @AppStorage(FileConverter.destKey) private var convDest = "downloads"
    @AppStorage(FileConverter.destPathKey) private var convDestPath = ""
    @AppStorage(FileConverter.autoClearKey) private var convAutoClear = true
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
                    .frame(width: 720)
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
                .frame(width: 720)
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
                // alignment: .top pins the header while the height catches up.
                // Switching spaces changes the content height instantly, but
                // panelContentHeight (this frame's height) trails by one runloop
                // — so for one frame the content and the frame disagree. A
                // default (center) frame splits that gap top and bottom, pushing
                // the header down (into a shorter stale frame) or clipping it off
                // the top (in a taller one) until the height lands: the header
                // visibly bobs. Top-aligned, the whole gap goes to the bottom
                // edge, so only the bottom moves and the header stays put.
                .frame(width: 368, height: min(panelContentHeight, maxPanelHeight), alignment: .top)
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
        let moduleKey: String   // module key activated (lifted out of inactive) on "enable"
        let title: L10nKey
        let body: L10nKey
    }
    // New features are appended here as the app gains them; each shows a one-time
    // top-of-panel banner to users who updated into it.
    private static let featureAnnouncements: [FeatureAnnouncement] = [
        .init(id: "torrent", moduleKey: "torrent",
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
                // Opting in = activate the module (lift it out of inactive onto
                // the current space) and, via placeModule, fetch the engine NOW
                // so the first real download doesn't stall behind a 26 MB install.
                placeModule(ann.moduleKey, onTab: currentSpaceID ?? tabsModel.tabs[0].id)
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
        .onChange(of: editUnit) { _, _ in syncKeyboardCapture() }
        .onChange(of: trackerEditing) { _, _ in syncKeyboardCapture() }
        .onChange(of: todosEditing) { _, _ in syncKeyboardCapture() }
        .onDisappear {
            model.panelKeyboardCaptured = false
            // A normal left-click / hotkey reopen does not fire the openTab
            // handler (openTab stays nil), and @State survives the popover
            // hide/show — so clear the picker here too, or the panel comes
            // back stuck on the icon grid instead of the space.
            iconPickerTabID = nil
        }
    }

    /// Every keyboard-capture source in one place: the timer digit editor
    /// (`editUnit`) and any focused tracker or to-do field. While one is live
    /// the controller keeps focus in the panel; once all drop, hand the
    /// keyboard back to the app underneath.
    private func syncKeyboardCapture() {
        let captured = editUnit != nil || trackerEditing || todosEditing
        model.panelKeyboardCaptured = captured
        if !captured { model.panelFocusChanged?() }
    }

    /// Keyboard time entry into the selected digit group: digits slide in from the
    /// right (0 → 2 gives :02). The group is picked by clicking/hovering the display.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // A focused tracker or to-do field owns the keyboard: Return commits
        // the field's own text, it must NOT drive the timer. Bailing here lets
        // the key fall through to the TextField's own onSubmit.
        guard !trackerEditing, !todosEditing else { return .ignored }
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
        case .escape:
            editUnit = nil
            return .handled
        case .return:
            // Return ends digit entry (like Esc) — it must NOT start the timer,
            // which starts/stops ONLY via its play button (Anton, 2026-07-19).
            // Without this, Return would fall through to `.ignored` while
            // `editUnit` keeps the keyboard captured, so the capture would never
            // release. Matches "capture ends on Esc/Enter" in the spec.
            if editUnit != nil {
                editUnit = nil
                return .handled
            }
            return .ignored
        default:
            // Return/Space no longer toggle the timer (Anton, 2026-07-19):
            // the timer starts/stops ONLY via its on-screen play button.
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
    // compact row must fit the widest control set + HH:MM:SS at "large":
    // [start 34 · reset 26 · spacer 6 · display · stopwatch 24] + 4×8 gaps
    // = 122pt of chrome inside the 340pt content width, leaving ~218pt for the
    // display. Dots "00:00:00" = 39 columns, so 39 × 5.3 ≈ 207 → ~329 total,
    // ~11pt of margin. 6.0 overflowed (39 × 6.0 = 234 → 356, off the edge).
    // text/units carry `minimumScaleFactor` so they never hard-overflow; they
    // shrink in step only to stay visually balanced with the smaller dots.
    private var dotCellCompact: CGFloat { digitsLarge ? 5.3 : 2.9 }
    private var textSizeCompact: CGFloat { digitsLarge ? 29 : 15.5 }
    private var unitsSizeCompact: CGFloat { digitsLarge ? 25.5 : 13.7 }

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

    /// Delete a tab from settings. HopCore sends the deleted tab's modules to
    /// the inactive bucket (hidden, not silently merged), which is why the UI
    /// asks for confirmation first. Settings is a separate window, so this can't
    /// touch the live panel screen; instead clear the saved active space if it
    /// pointed at the deleted tab, so the panel reopens on a valid space.
    private func deleteTab(_ id: UUID) {
        mutateTabs { $0.deleteTab(id) }
        if activeSpaceRaw == id.uuidString { activeSpaceRaw = "" }
        // in-panel path (if ever shown there): fall back off the deleted space
        if screen == .space(id), let first = tabsModel.tabs.first {
            switchToSpace(first.id)
        }
        // a stale picker / confirmation for the gone tab would dangle open
        if iconPickerTabID == id { iconPickerTabID = nil }
        if confirmDeleteTab == id { confirmDeleteTab = nil }
    }

    private func switchToSpace(_ id: UUID) {
        screen = .space(id)
        activeSpaceRaw = id.uuidString
    }

    // MARK: - Settings module table (columns = tabs + inactive)

    private static let tableCoordinateSpace = "modTable"

    /// Frames of the drop columns (tab uuid string / "inactive") and of the
    /// module chips, measured in the table's coordinate space so a drag can be
    /// resolved to a target column and an insert index.
    private struct ColumnFrameKey: PreferenceKey {
        static let defaultValue: [String: CGRect] = [:]
        static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }
    private struct ChipFrameKey: PreferenceKey {
        static let defaultValue: [String: CGRect] = [:]
        static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }

    /// One tab column: header (icon picker + "#N" + hover delete) over its
    /// module chips. The whole column offsets while its header is being dragged
    /// to reorder tabs; it highlights when it is the chip drop target.
    private func tabColumn(_ tab: PanelTab, number: Int) -> some View {
        let headerDragging = dragHeaderTab == tab.id
        return VStack(spacing: 8) {
            tabColumnHeader(tab, number: number)
            columnChips(keys: tab.moduleKeys, columnID: tab.id.uuidString, inactive: false)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(6)
        .background(dropColumn == tab.id.uuidString ? Theme.chipBg : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.divider, lineWidth: 1))
        .background(columnFrameReader(tab.id.uuidString))
        .opacity(headerDragging ? 0.5 : 1)
        .offset(x: headerDragging ? dragHeaderTranslation : 0)
        .zIndex(headerDragging ? 2 : 0)
    }

    /// Tab column header. Tapping the icon (or its rotating chevron) toggles the
    /// full-width icon picker below the table; the hover-only xmark opens an
    /// inline delete confirmation. A horizontal drag on the header reorders the
    /// tab columns (`moveTab`).
    private func tabColumnHeader(_ tab: PanelTab, number: Int) -> some View {
        let expanded = iconPickerTabID == tab.id
        return HStack(spacing: 4) {
            Button {
                iconPickerTabID = expanded ? nil : tab.id
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(5)
            .help(t(.tabChangeIcon).capitalizedFirst)
            .animation(.easeInOut(duration: 0.15), value: expanded)
            Text("#\(number)")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
            if tabsModel.tabs.count > 1 {
                Button { confirmDeleteTab = tab.id } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(4)
                .help(t(.tabDelete).capitalizedFirst)
                .opacity(hoveredTabRow == tab.id ? 1 : 0)
                .allowsHitTesting(hoveredTabRow == tab.id)
            }
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hoveredTabRow = tab.id } else if hoveredTabRow == tab.id { hoveredTabRow = nil }
        }
        .gesture(headerDragGesture(tab.id))
    }

    /// The permanent inactive column: a plain label header (no icon, no delete)
    /// over dimmed chips of every hidden module.
    private var inactiveColumn: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(t(.modulesInactive))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 22)
            columnChips(keys: tabsModel.inactive, columnID: "inactive", inactive: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(6)
        .background(dropColumn == "inactive" ? Theme.chipBg : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Theme.divider, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        .background(columnFrameReader("inactive"))
    }

    /// The stacked module chips of one column. An empty column keeps a small
    /// clear area so it is still a reachable drop target.
    private func columnChips(keys: [String], columnID: String, inactive: Bool) -> some View {
        VStack(spacing: 6) {
            ForEach(keys, id: \.self) { key in
                moduleChip(key, inactive: inactive)
            }
            if keys.isEmpty {
                Color.clear.frame(height: 26)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .top)
    }

    /// A draggable module chip. Dragging it reports a live drop-column highlight
    /// and, on release, moves the module into that column at the pointer's row.
    private func moduleChip(_ key: String, inactive: Bool) -> some View {
        let dragging = dragChip == key
        return Text(moduleTitle(key))
            .font(Theme.mono(11))
            .foregroundStyle(inactive ? Theme.textTertiary : Theme.textPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
            .background(chipFrameReader(key))
            .opacity(dragging ? 0.35 : 1)
            .offset(dragging ? dragChipTranslation : .zero)
            .zIndex(dragging ? 3 : 0)
            .gesture(chipDragGesture(key))
    }

    private var addColumnStub: some View {
        Button {
            mutateTabs { $0.addTab(icon: firstUnusedIcon) }
        } label: {
            VStack(spacing: 0) {
                Image(systemName: "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(height: 22)
                Spacer(minLength: 0)
            }
            .frame(width: 30)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(6)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.divider, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(8)
        .help(t(.tabNew).capitalizedFirst)
    }

    // MARK: - Table geometry + drag

    private func columnFrameReader(_ id: String) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ColumnFrameKey.self,
                value: [id: geo.frame(in: .named(Self.tableCoordinateSpace))]
            )
        }
    }

    private func chipFrameReader(_ key: String) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ChipFrameKey.self,
                value: [key: geo.frame(in: .named(Self.tableCoordinateSpace))]
            )
        }
    }

    /// The drop column whose frame spans `point.x`, or the nearest one if the
    /// pointer sits in a gap or past the edge. The "+" stub is not a drop target.
    private func columnID(at point: CGPoint) -> String? {
        if let hit = columnFrames.first(where: { $0.value.minX <= point.x && point.x <= $0.value.maxX })?.key {
            return hit
        }
        return columnFrames.min(by: { abs($0.value.midX - point.x) < abs($1.value.midX - point.x) })?.key
    }

    private func chipDragGesture(_ key: String) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.tableCoordinateSpace))
            .onChanged { value in
                if dragChip == nil { dragChip = key }
                dragChipTranslation = value.translation
                dropColumn = columnID(at: value.location)
            }
            .onEnded { value in
                applyChipDrop(key: key, to: columnID(at: value.location), at: value.location)
                dragChip = nil
                dragChipTranslation = .zero
                dropColumn = nil
            }
    }

    /// Resolve a chip release to a column + insert index and write it through the
    /// tabs model. Same helper handles cross-column moves and same-column
    /// reorders: `placeModule`/`deactivateModule` both remove-then-insert.
    private func applyChipDrop(key: String, to columnID: String?, at point: CGPoint) {
        guard let columnID else { return }
        let targetKeys: [String]
        if columnID == "inactive" {
            targetKeys = tabsModel.inactive.filter { $0 != key }
        } else if let uuid = UUID(uuidString: columnID) {
            targetKeys = (tabsModel.tabs.first { $0.id == uuid }?.moduleKeys ?? []).filter { $0 != key }
        } else {
            return
        }
        // insert index = how many of the column's OTHER chips sit above the drop
        let index = targetKeys.filter {
            (chipFrames[$0]?.midY ?? .greatestFiniteMagnitude) < point.y
        }.count
        if columnID == "inactive" {
            deactivateModule(key, at: index)
        } else if let uuid = UUID(uuidString: columnID) {
            placeModule(key, onTab: uuid, at: index)
        }
    }

    /// Horizontal header drag reorders tab columns. Commits on release from the
    /// pointer's column against the measured column frames (same slot-detection
    /// family as the chip drop); no live column shuffle keeps it robust.
    private func headerDragGesture(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.tableCoordinateSpace))
            .onChanged { value in
                if dragHeaderTab == nil {
                    dragHeaderTab = id
                    iconPickerTabID = nil   // an open picker would fight the offset
                }
                dragHeaderTranslation = value.translation.width
            }
            .onEnded { value in
                withAnimation(.easeInOut(duration: 0.15)) {
                    if let from = tabsModel.tabs.firstIndex(where: { $0.id == id }),
                       let targetID = columnID(at: value.location),
                       let to = tabsModel.tabs.firstIndex(where: { $0.id.uuidString == targetID }),
                       to != from {
                        mutateTabs { $0.moveTab(from: from, to: to) }
                    }
                    dragHeaderTab = nil
                    dragHeaderTranslation = 0
                }
            }
    }

    /// Inline delete confirmation shown full-width below the table (a narrow
    /// column can't hold the sentence): the house-style question + delete/cancel.
    private func deleteTabConfirmBar(_ id: UUID) -> some View {
        HStack(spacing: 12) {
            Text(t(.tabDeleteConfirm))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Button { deleteTab(id) } label: {
                HoverLabel(text: t(.trackerDelete), size: 10, color: Theme.accentRed)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { confirmDeleteTab = nil } label: {
                HoverLabel(text: t(.quitCancel), size: 10, color: Theme.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Icon picker grid, shown inline under the module table when a column's icon
    /// is tapped. Full width (a single column is too narrow for the 6-wide grid).
    /// Inline rather than a nested popover (which risks dismissing the panel).
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

    // "system"/"tracker"/"todos" are deliberately NOT here: they live only in
    // the tabs model (the monitor tab and the tracker+todos tab from `migrate`).
    // Adding one here would make `moduleOrder` append it AND `migrate` place it
    // in its own tab — a duplicate key the tabs model rejects.
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
            model.ensure(modules: allModules + ["system", "tracker", "todos"])
            // Migrate legacy visibility BEFORE seeding: a legacy
            // `showTrackerModule=false` state must deactivate the tracker
            // first, so `seedCanonicalLayout` reads the true active set
            // instead of rebuilding a tab around a module the user turned off.
            migrateModuleVisibility(&model)
            seedCanonicalLayout(&model)
            return model
        }
        var model = PanelTabsModel.migrate(moduleOrder: moduleOrder)
        model.ensure(modules: allModules + ["system", "tracker", "todos"])
        // Apply the legacy toggles on EVERY fresh-migrate call (it is
        // deterministic — same toggles, same result), NOT behind the one-shot
        // flag: `tabsModel` recomputes many times per render, and if a later
        // recompute still sees an empty `panelTabsRaw` it must produce the same
        // hidden set, or torrent (default off) would flicker back visible.
        deactivateOffModules(&model)
        UserDefaults.standard.set(model.encoded(), forKey: SettingsKey.panelTabs)
        // A fresh migrate already gives the system monitor and the tracker
        // each their own tab (with todos paired beside the tracker) — the
        // same shape `seedCanonicalLayout` converges decoded states onto —
        // and has just applied the toggles, so claim every one-shot flag
        // here too, so none of them rerun for a new install.
        UserDefaults.standard.set(true, forKey: SettingsKey.trackerTabSeeded)
        UserDefaults.standard.set(true, forKey: SettingsKey.todosSeeded)
        UserDefaults.standard.set(true, forKey: SettingsKey.moduleVisibilityMigrated)
        UserDefaults.standard.set(true, forKey: SettingsKey.canonicalLayoutSeeded)
        return model
    }

    /// Every module's legacy visibility toggle: UserDefaults key + its default.
    private static let legacyVisibilityToggles: [(module: String, key: String, defaultOn: Bool)] = [
        ("timer", "showTimerModule", true),
        ("awake", "showAwakeModule", true),
        ("clipboard", "showClipboardModule", true),
        ("convert", "showConvertModule", true),
        ("windows", "showWindowsModule", true),
        ("speedtest", "showSpeedtestModule", true),
        ("system", "showSystemModule", true),
        ("tracker", "showTrackerModule", true),
        ("torrent", "showTorrentModule", false),
    ]

    /// Hide every module whose legacy toggle is OFF. `UserDefaults.bool` reads a
    /// missing key as false, so an unset toggle falls back to the module's real
    /// default (otherwise everything a user never touched — most modules, default
    /// ON — would migrate to hidden). Deterministic and idempotent.
    private static func deactivateOffModules(_ model: inout PanelTabsModel) {
        let defaults = UserDefaults.standard
        for toggle in legacyVisibilityToggles {
            let on = defaults.object(forKey: toggle.key) == nil
                ? toggle.defaultOn
                : defaults.bool(forKey: toggle.key)
            if !on, !model.inactive.contains(toggle.module) {
                model.deactivate(module: toggle.module)
            }
        }
    }

    /// One-shot for models saved BEFORE the inactive bucket existed (real
    /// updating users): fold the old toggles in once, then never again so the
    /// user's later re-activations stick. The fresh-migrate path sets the flag
    /// itself, so this only ever fires on a decoded legacy model.
    private static func migrateModuleVisibility(_ model: inout PanelTabsModel) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: SettingsKey.moduleVisibilityMigrated) else { return }
        deactivateOffModules(&model)
        defaults.set(true, forKey: SettingsKey.moduleVisibilityMigrated)
        defaults.set(model.encoded(), forKey: SettingsKey.panelTabs)
    }

    /// Reactivate a module from OUTSIDE a live panel (AppDelegate file-open,
    /// onboarding): lift it out of the inactive bucket onto the first tab,
    /// persisting straight to UserDefaults. No-op if it isn't inactive.
    static func activateStoredModule(_ key: String) {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: SettingsKey.panelTabs) ?? ""
        guard var model = PanelTabsModel.decode(raw),
              model.inactive.contains(key),
              let first = model.tabs.first else { return }
        model.move(module: key, toTab: first.id)
        defaults.set(model.encoded(), forKey: SettingsKey.panelTabs)
    }

    /// Hide a module from OUTSIDE a live panel (onboarding): send it to the
    /// inactive bucket. No-op if it is unknown or already inactive.
    static func deactivateStoredModule(_ key: String) {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: SettingsKey.panelTabs) ?? ""
        guard var model = PanelTabsModel.decode(raw), !model.inactive.contains(key) else { return }
        model.deactivate(module: key)
        defaults.set(model.encoded(), forKey: SettingsKey.panelTabs)
    }

    /// Whether `key` currently sits in the inactive bucket (used by AppDelegate
    /// to decide the torrent engine prefetch after onboarding).
    static func storedModuleIsInactive(_ key: String) -> Bool {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.panelTabs) ?? ""
        return PanelTabsModel.decode(raw)?.inactive.contains(key) ?? false
    }

    /// Called once, right after onboarding reconciles the fresh install's module
    /// choices into the membership model. The launch-time fresh migrate always
    /// lays down the canonical three spaces (general | system | tracker+todos),
    /// so turning the monitor, tracker AND to-dos off in onboarding leaves their
    /// spaces empty — and the app must not open onto a blank tab. Drop every
    /// empty space EXCEPT the first: space 1 always stays (it still holds the
    /// speed test, which has no onboarding toggle, so it is never truly empty),
    /// even if thin. This mirrors what `seedCanonicalLayout` does for decoded
    /// legacy models — it only ever creates a system/tracker space when that
    /// space has an active module — closing the same gap on the fresh-migrate
    /// path, whose fixed `PanelTabsModel.migrate` shape cannot prune itself.
    static func dropEmptyOnboardingSpaces() {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: SettingsKey.panelTabs) ?? ""
        guard var model = PanelTabsModel.decode(raw), model.tabs.count > 1 else { return }
        model.tabs = [model.tabs[0]] + model.tabs.dropFirst().filter { !$0.moduleKeys.isEmpty }
        defaults.set(model.encoded(), forKey: SettingsKey.panelTabs)
    }

    /// One-shot canonical layout repair for decoded legacy models — including
    /// any state left mid-shuffled by the OLD per-module seeds this replaces
    /// (`seedSystemTab`, `seedTrackerTab`, `seedTodos`; each nudged ONE module
    /// without ever looking at the whole board, which is exactly how a real
    /// state went wrong: a second tab that already held the tracker got
    /// "system" stacked onto it instead of a "display" tab of its own).
    /// Rather than resume patching individual modules into place, this
    /// rebuilds the ENTIRE active layout in one shot, converging on the same
    /// shape a fresh install gets:
    ///   - tab 1: every other active module, in the order first encountered
    ///     scanning the existing tabs front to back, keeping tab 1's current
    ///     icon
    ///   - tab 2: "system" alone (icon "display") — only if system is active
    ///   - tab 3: "tracker" then "todos" (icon "clock") — only whichever of
    ///     the two are active
    /// `inactive` is left completely untouched: the user's hidden choices
    /// stay hidden exactly where they left them — this only rearranges what
    /// is ON a tab. Any tab beyond these three (a user's own extra space)
    /// dissolves; its active modules were already folded into tab 1 above, so
    /// nothing is lost, just re-homed. This SUPERSEDES `trackerTabSeeded`/
    /// `todosSeeded`: `canonicalLayoutSeeded` is a brand-new flag, false for
    /// every decoded state (even ones where those two already fired), so it
    /// runs exactly once for everybody and claims all three flags together —
    /// there is no leftover call path that could still nudge a single module
    /// after the board has already been canonicalized.
    private static func seedCanonicalLayout(_ model: inout PanelTabsModel) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: SettingsKey.canonicalLayoutSeeded) else { return }
        defer {
            defaults.set(true, forKey: SettingsKey.canonicalLayoutSeeded)
            defaults.set(true, forKey: SettingsKey.trackerTabSeeded)
            defaults.set(true, forKey: SettingsKey.todosSeeded)
        }

        let managed: Set<String> = ["system", "tracker", "todos"]
        var seen = Set<String>()
        var primaryModules: [String] = []
        for tab in model.tabs {
            for key in tab.moduleKeys where !managed.contains(key) && !seen.contains(key) {
                seen.insert(key)
                primaryModules.append(key)
            }
        }

        var canonical = [PanelTab(icon: model.tabs[0].icon, moduleKeys: primaryModules)]
        if !model.inactive.contains("system") {
            canonical.append(PanelTab(icon: "display", moduleKeys: ["system"]))
        }
        let clockModules = ["tracker", "todos"].filter { !model.inactive.contains($0) }
        if !clockModules.isEmpty {
            canonical.append(PanelTab(icon: "clock", moduleKeys: clockModules))
        }
        model.tabs = canonical

        // The rebuild mints fresh tab ids, so a persisted `activeSpaceID`
        // pointing into the old board can now be dangling. `effectiveSpaceID`
        // already falls back gracefully at render time either way, but reset
        // the stored value too when it no longer resolves, instead of leaving
        // it stale.
        let activeSpaceKey = "activeSpaceID"
        if let raw = defaults.string(forKey: activeSpaceKey), let id = UUID(uuidString: raw),
           !model.tabs.contains(where: { $0.id == id }) {
            defaults.set("", forKey: activeSpaceKey)
        }

        defaults.set(model.encoded(), forKey: SettingsKey.panelTabs)
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

    /// Visibility is membership: a module shows iff it is NOT in the inactive
    /// bucket. Torrent keeps one extra rule on top — an installed engine with
    /// zero torrents may hide its empty add-card unless the user opts to keep it.
    private func moduleVisible(_ key: String) -> Bool {
        guard !tabsModel.inactive.contains(key) else { return false }
        if key == "torrent",
           model.torrent.torrents.isEmpty,
           case .installed = model.torrent.installer.state,
           !torrentShowWhenEmpty {
            return false
        }
        return true
    }

    /// The single choke point for placing a module ON a tab (settings-table
    /// drag, right-click "move to", banner enable). Lifting torrent out of the
    /// inactive bucket is the one activation with a side effect — fetch its
    /// engine here so no caller can forget.
    private func placeModule(_ key: String, onTab tabID: UUID, at position: Int? = nil) {
        let wasInactive = tabsModel.inactive.contains(key)
        mutateTabs {
            $0.move(module: key, toTab: tabID)
            if let position { $0.reorder(module: key, inTab: tabID, to: position) }
        }
        if key == "torrent", wasInactive { model.torrent.prefetchEngineIfNeeded() }
    }

    /// Hide a module: send it to the permanent inactive bucket.
    private func deactivateModule(_ key: String, at position: Int? = nil) {
        mutateTabs {
            $0.deactivate(module: key)
            if let position { $0.reorder(inInactive: key, to: position) }
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
        case "todos": return t(.todosLabel)
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
            TrackerView(tracker: model.tracker, lang: lang,
                        onEditingChanged: { trackerEditing = $0 })
                .id(model.themeVersion)
        case "todos":
            TodosView(todos: model.todos, lang: lang,
                      onEditingChanged: { todosEditing = $0 })
                .id(model.themeVersion)
        default: EmptyView()
        }
    }

    /// A panel module wrapped with its right-click "move to …" menu: one item
    /// per OTHER tab plus a final "inactive" destination that hides it. The wrap
    /// lives on the module container, so a module's own inner context menus and
    /// gestures win locally. There is always at least the "inactive" target, so
    /// the menu is never empty. (A hidden module is simply no longer rendered,
    /// so there is no inverse "activate" context menu — that happens in settings.)
    @ViewBuilder private func moduleBlock(_ key: String, in tabID: UUID) -> some View {
        let others = tabsModel.tabs.enumerated().filter { $0.element.id != tabID }
        moduleContent(key)
            .contextMenu {
                Menu(t(.moduleMoveTo).capitalizedFirst) {
                    ForEach(others, id: \.element.id) { index, tab in
                        Button {
                            placeModule(key, onTab: tab.id)
                        } label: {
                            Label("#\(index + 1)", systemImage: tab.icon)
                        }
                    }
                    Button {
                        deactivateModule(key)
                    } label: {
                        Label(t(.modulesInactive).capitalizedFirst, systemImage: "eye.slash")
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
            // "modules & tabs" is its own top-level section, not nested under
            // "general" — a tab-in-tab was rejected. Five chips at their natural
            // width fit one line in the 720pt window; `wraps` lets the longest
            // languages (fr/tr) flow onto a second line instead of truncating,
            // the same overflow handling the about switcher already uses.
            SectionChips(items: [
                ("general", t(.aboutTabGeneral)),
                ("timer", t(.aboutTabTimer)),
                ("modules", t(.otherModulesLabel)),
                ("monitor", t(.tabSystem)),
                ("layout", t(.settingsTabLayout)),
            ], selection: $settingsSection, wraps: true)

            switch settingsSection {
            case "timer":
                timerSettings
            case "monitor":
                thresholdsSection
            case "modules":
                modulesSettings
            case "layout":
                layoutSettings
            default:
                generalBasics
            }
        }
        .padding(.vertical, 4)
    }

    /// Everyday options: theme, language, launch, sounds, updates, app icon,
    /// hotkeys. Everything on the "general" section EXCEPT the spaces/module
    /// arrangement, which is its own top-level "modules & tabs" section.
    private var generalBasics: some View {
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

            hotkeysSection
        }
    }

    /// The panel layout as one table: a column per space plus a permanent
    /// "inactive" column. Module chips are dragged between and within columns
    /// (that IS the visibility control — no on/off toggles); a column header is
    /// dragged to reorder spaces; the "+" stub adds one. The icon picker and the
    /// delete confirmation open full-width beneath the table (a column is too
    /// narrow for either).
    private var layoutSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t(.modulesLabel))
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(tabsModel.tabs.enumerated()), id: \.element.id) { index, tab in
                    tabColumn(tab, number: index + 1)
                }
                inactiveColumn
                if tabsModel.tabs.count < PanelTabsModel.maxTabs {
                    addColumnStub
                }
            }
            .coordinateSpace(name: Self.tableCoordinateSpace)
            .onPreferenceChange(ColumnFrameKey.self) { columnFrames = $0 }
            .onPreferenceChange(ChipFrameKey.self) { chipFrames = $0 }

            // The confirmation and the picker are mutually exclusive and both
            // open below the table, where there is room for them.
            if let id = confirmDeleteTab {
                deleteTabConfirmBar(id)
            } else if let id = iconPickerTabID {
                iconPickerGrid(for: id)
            }
        }
        .onDisappear {
            // @State survives the settings window's hide/show, so a window
            // closed mid-drag would reopen with a ghost chip frozen at the drag
            // point. Clear the chip and header drag state here — mirrors
            // TrackerView's resetDrag() and the gesture `onEnded` handlers.
            dragChip = nil
            dragChipTranslation = .zero
            dropColumn = nil
            dragHeaderTab = nil
            dragHeaderTranslation = 0
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
