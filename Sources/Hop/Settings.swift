import Foundation

/// The app's identifier for Application Support directories and Launch
/// Services registration: the real bundle id when one exists (production
/// or dev build), otherwise a dedicated sandbox id for bundle-less runs
/// (raw `swift build` binary, `--snapshot` / `--torrent-selftest` probes).
///
/// MUST NEVER fall back to the production id ("com.antonshakirov.minimo"):
/// a bundle-less process reading or writing under that folder would touch
/// the real user's production data — this already happened once (a probe
/// run pruned a production clipboard image). Bundle-less runs get their
/// own "…minimo.cli" folder instead, so they can never see or mutate real
/// user data.
extension Bundle {
    /// The ONE production bundle id. Every other id — the ".dev" parallel app,
    /// a raw `swift build` binary (nil id), a snapshot probe — is a dev/test
    /// instance. Never change it (see the signing/version rules).
    static let productionIdentifier = "com.antonshakirov.minimo"

    static var storageIdentifier: String {
        main.bundleIdentifier ?? "\(productionIdentifier).cli"
    }

    /// A non-production build: anything whose bundle id is not EXACTLY the
    /// production id — the ".dev" app AND the bundle-less debug/snapshot binary
    /// (nil id). The SINGLE rule the auto-updater (stay offline), the menu-bar
    /// dev-mark and the Finder-icon dev-badge all share; a `.dev`-suffix-only
    /// heuristic wrongly treated a bundle-less run as production and would let
    /// it auto-update.
    static var isDevBuild: Bool {
        main.bundleIdentifier != productionIdentifier
    }
}

enum SettingsKey {
    /// While one of Hop's own windows is open, put the app in the Dock like any
    /// other — the window is then reachable by clicking the icon instead of
    /// going through the panel. ON by default; OFF keeps Hop invisible outside
    /// the menu bar for people who chose it for exactly that.
    static let showWindowsInDock = "showWindowsInDock"
    static let showMenuBarCountdown = "showMenuBarCountdown"
    /// Show the active tracker task's ticking "today" time in the menu bar; off by default.
    static let trackerTimeInBar = "trackerTimeInBar"
    static let alertMode = "alertMode"
    static let appLanguage = "appLanguage" // "auto" or an AppLanguage code
    /// Red "!" on the left of the icon when the monitor hits the red zone; off by default.
    static let menuBarRedAlert = "menuBarRedAlert"
    /// Colour the menu-bar icon's corner badges (green/yellow/orange/red). ON by
    /// default; OFF renders every badge monochrome, telling same-corner pairs
    /// apart by shape (filled vs outline).
    static let coloredIndicators = "coloredIndicators"
    /// JSON-encoded PanelTabsModel: the user's spaces (icon tabs) and their module keys.
    static let panelTabs = "panelTabs"
    /// Which onboarding step to reopen on. SPEC: docs/spec.md — "Onboarding".
    static let onboardingStep = "onboardingStep"
    static let onboardingWantsApps = "onboardingWantsApps"
    static let onboardingLaunchAtLogin = "onboardingLaunchAtLogin"
    /// One-shot flag: models saved before the tracker had its own tab get the
    /// tracker lifted into a fresh "clock" tab exactly once. Set on the fresh
    /// migrate path too, so the seed never runs for new installs.
    static let trackerTabSeeded = "trackerTabSeeded"
    /// One-shot flag: models saved before the to-do module existed get "todos"
    /// placed directly after "tracker" exactly once. Set on the fresh migrate
    /// path too (migrate already pairs them), so the seed never runs for new
    /// installs.
    static let todosSeeded = "todosSeeded"
    /// One-shot flag: the legacy per-module `show*Module` toggles are read once
    /// and every OFF module is moved into the inactive bucket, after which
    /// visibility is pure membership and the toggles are never read again.
    static let moduleVisibilityMigrated = "moduleVisibilityMigrated"
    /// One-shot flag: the opt-in modules (the eyedropper and screen text) are
    /// moved into the inactive bucket exactly once, right after `ensure` places
    /// them — they ship hidden, and an update must not push a designer tool onto
    /// everyone's panel. Set on the fresh migrate path too, so a user who
    /// activates one later keeps it.
    static let optInModulesSeeded = "optInModulesSeeded"
    /// The same one-shot, PER RELEASE. The original key was claimed back in
    /// 1.5.0, so a later release's new module would never be swept into the
    /// inactive bucket and would simply appear in everyone's panel — which is
    /// exactly what the sweep exists to prevent (Anton, 2026-07-25: nothing
    /// appears that was not ticked).
    static let optInModulesSeeded170 = "optInModulesSeeded170"
    /// One-shot flag: decoded legacy models (and any state left mid-shuffled
    /// by the older per-module seeds this superseded) get their whole active
    /// layout rebuilt into the canonical three-tab shape exactly once. Set on
    /// the fresh migrate path too, so the seed never runs for new installs.
    static let canonicalLayoutSeeded = "canonicalLayoutSeeded"
    /// The reminder signal: three independent switches, all ON by default. These
    /// ARE the documented exception to "no per-badge switches" — a reminder is a
    /// one-off user event rather than an app state, so its signal is a preference
    /// of the same family as the timer's finish signal.
    static let todoRemindBanner = "todoRemindBanner"
    static let todoRemindSound = "todoRemindSound"
    static let todoRemindMark = "todoRemindMark"
    /// Important tasks rise to the top of their list. OFF by default: with it off,
    /// marking a task changes nothing about where it sits.
    static let todoImportantOnTop = "todoImportantOnTop"
    static let trackerImportantOnTop = "trackerImportantOnTop"
    /// Saving a clipboard entry to a file: an extra icon in every text row.
    /// OFF by default — most people never need it, and an icon that does nothing
    /// for them is an icon in the way. `…Ask` picks the system save panel over
    /// the Desktop, which is where an unasked save lands.
    static let clipboardToFile = "clipboardToFile"
    static let clipboardToFileAsk = "clipboardToFileAsk"
    /// Which of txt / md / pdf / docx an entry is saved as. Stored as the raw
    /// name, read through `ClipboardDocument.Format.named` so an unknown value
    /// falls back to text rather than refusing to save.
    static let clipboardToFileFormat = "clipboardToFileFormat"
    /// The green dot the menu-bar icon carries while a VPN tunnel is up. ON by
    /// default. The second badge with a switch of its own: a tunnel is a state
    /// somebody else's app owns, and whether it is worth a mark is the user's
    /// call, not ours (Anton, 2026-07-29).
    static let vpnMenuBarMark = "vpnMenuBarMark"
    /// Whether switching a VPN off also takes it out of the network set, so its
    /// own on-demand rules cannot bring it back. ON by default: a switch that
    /// does not switch anything off is not a switch (Anton, 2026-07-30).
    static let vpnHoldOff = "vpnHoldOff"
    /// The converter, the archives and the uninstaller drawn as ONE row instead of
    /// three. They are the same shape of thing — a row that opens a window and
    /// takes files — and three of them cost a crowded space three lines.
    static let toolsOneRow = "toolsOneRow"
    /// Which day the week starts on in the reminder's weekday row: "auto" follows
    /// the system's region, and the two explicit values override it.
    static let firstWeekday = "firstWeekday"
    /// Defaults that are not `false`/nil/0. Registered once at launch.
    static let registeredDefaults: [String: Any] = [
        todoRemindBanner: true,
        todoRemindSound: true,
        todoRemindMark: true,
        vpnMenuBarMark: true,
    ]
}

/// Highlight thresholds for the system tab: at which value yellow and red kick in.
/// Battery semantics are inverted: below the threshold is worse.
enum Thresholds {
    static let loadYellowKey = "thLoadYellow"
    static let loadRedKey = "thLoadRed"
    static let diskYellowKey = "thDiskYellow"
    static let diskRedKey = "thDiskRed"
    static let battYellowKey = "thBattYellow"
    static let battRedKey = "thBattRed"
    /// Swap as a share of physical RAM. Deliberately NOT the old `thMemYellow`
    /// key: that one held a percentage of `(used + swap) ÷ RAM` whose "normal"
    /// started at 110, and inheriting a 110 here would mean "warn when swap
    /// passes 110% of RAM", which is silence.
    static let swapYellowKey = "thSwapYellow"
    static let swapRedKey = "thSwapRed"

    // temperature has no threshold: the row color follows macOS's own thermal
    // verdict (see HopCore.ThermalLevel). Apple publishes no limit and Apple
    // Silicon runs at 90-100 C under load, so any number here would be invented.
    static let loadYellowDefault = 80
    static let loadRedDefault = 95
    // memory: how much of a RAM's worth is allowed to sit in swap before the
    // row speaks up. macOS's own pressure signal still colours the row and is
    // never overridden — this only catches what that signal is blind to, a
    // machine quietly holding gigabytes on disk (see HopCore.MemoryStrain).
    static let swapYellowDefault = 25
    static let swapRedDefault = 50
    static let diskYellowDefault = 85
    static let diskRedDefault = 95
    static let battYellowDefault = 30
    static let battRedDefault = 15

    /// The removed temperature keys are swept too, so a machine that upgrades
    /// from a version with a 70/90 setting does not keep dead defaults on disk.
    static let allKeys = [
        loadYellowKey, loadRedKey,
        diskYellowKey, diskRedKey, battYellowKey, battRedKey,
        swapYellowKey, swapRedKey,
        // dead keys from versions that had them, swept so an upgrade does not
        // keep defaults nothing reads any more
        "thTempYellow", "thTempRed", "thMemYellow", "thMemRed",
    ]

    static func resetAll() {
        for key in allKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

enum AlertMode: String, CaseIterable, Identifiable {
    case soundAndBanner
    case soundOnly
    case silent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .soundAndBanner: return "sound + banner"
        case .soundOnly: return "sound only"
        case .silent: return "silent"
        }
    }

    var icon: String {
        switch self {
        case .soundAndBanner: return "bell.and.waves.left.and.right" // sound+banner: a bell with waves
        case .soundOnly: return "speaker.wave.2"
        case .silent: return "bell.slash"
        }
    }

    static var current: AlertMode {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.alertMode) ?? ""
        return AlertMode(rawValue: raw) ?? .soundAndBanner
    }
}
