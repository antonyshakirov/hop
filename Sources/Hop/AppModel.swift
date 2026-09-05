import Combine
import Foundation
import HopCore

@MainActor
final class AppModel: ObservableObject {
    /// For emergency cleanup of awake on app exit.
    static var sharedKeepAwake: KeepAwakeController?

    let engine = TimerEngine()
    let keepAwake: KeepAwakeController
    let stats: SystemStatsController
    let clipboard: ClipboardController
    let updater = UpdateChecker()
    let converter = FileConverter()
    let speedTest = SpeedTestController()
    let torrent = TorrentController()
    let tracker: TrackerController
    let todos: TodosController
    /// Modules that PRODUCE clipboard entries; they take the clipboard
    /// controller, so they are built in `init` after it exists.
    let colorPicker: ColorPickerController
    let screenText: ScreenTextController
    let archive = ArchiveController()
    let keyboardLock = KeyboardLockController()
    let vpn: VPNController
    let uninstall = UninstallController()
    let appShelves: AppShelvesController

    /// Last time the user actively touched Hop. The updater installs a found
    /// release only after a long enough quiet gap (see UpdateInstallPolicy),
    /// so we stamp it on panel opens, hotkeys, window opens and conversions.
    let activity = ActivityTracker()

    /// Whether the panel popover is showing right now (wired by StatusItemController).
    /// The updater treats an open panel as active use and won't relaunch under it.
    var isPanelOpen: (() -> Bool)?

    /// Incremented on every theme change: .id(themeVersion) recreates views
    /// that SwiftUI would otherwise not redraw (their inputs did not change).
    @Published var themeVersion = 0

    /// Desired content height of the converter window (from the view's PreferenceKey).
    @Published var converterContentHeight: CGFloat = 0

    /// Desired content height of the archive window — it opens as tall as the
    /// drop plate and grows only when there are jobs to show.
    @Published var archiveContentHeight: CGFloat = 0
    @Published var uninstallContentHeight: CGFloat = 0

    /// Desired content height of the recognition window — the plate alone until
    /// a result exists, then room for the text as well.
    @Published var screenTextContentHeight: CGFloat = 0

    /// Request to open a specific screen (from the right-click menu).
    @Published var openTab: PanelView.InitialScreen?
    /// Close the popover (for "copy and paste").
    var closePanel: (() -> Void)?
    /// Bring the panel back on a module's own terms — the eyedropper closes it
    /// to get out of the way of the loupe and owes the user the result
    /// (Anton, 2026-07-26).
    var reopenPanel: ((PanelView.InitialScreen?) -> Void)?
    /// The panel needs the keyboard right now (digit entry into the display).
    /// Everything else is mouse-only: keystrokes belong to the app underneath.
    var panelKeyboardCaptured = false
    /// Ping after panel clicks / edit-state changes: the status item controller
    /// decides whether to hand focus back to the app under the panel.
    var panelFocusChanged: (() -> Void)?
    /// Open the standalone settings window.
    var openSettingsWindow: (() -> Void)?
    /// Open the standalone converter window.
    var openConverterWindow: (() -> Void)?
    /// Open the standalone archive window — a drop target that survives a drag,
    /// which the panel's popover cannot be.
    var openArchiveWindow: (() -> Void)?
    /// Open the uninstaller window: an app is dropped there, and the window is
    /// the only drop target that survives a drag.
    var openUninstallWindow: (() -> Void)?
    /// Open the recognition window: where a picture is dropped or pasted, and
    /// where the recognized text is shown.
    var openScreenTextWindow: (() -> Void)?
    /// A page the settings window should jump to on its next open, consumed once
    /// by the window itself. The window remembers the page it was left on, so a
    /// caller that needs a particular one has to say which.
    @Published var settingsSectionRequest: String?
    /// Open the torrent add sheet (file selection + destination) for a source.
    /// The sheet fetches the file list itself and shows a "fetching…" state, so
    /// the window appears instantly on a magnet paste. Presented as a window,
    /// like the converter — the popover collapses on any outside click and
    /// cannot host a multi-step choice.
    var openTorrentAddSheet: ((TorrentController.AddSource) -> Void)?
    /// Quit with confirmation if the timer is running or sleep prevention is active.
    var requestQuit: (() -> Void)?
    /// Bring already-open auxiliary windows (converter/settings/about) back
    /// to the front — they sink behind other apps' windows on deactivate.
    var raiseOpenWindows: (() -> Void)?
    /// Instantly apply a theme change to all windows and the popup.
    var refreshTheme: (() -> Void)?

    private var forwarders: [AnyCancellable] = []

    /// A preview model feeds the onboarding's live module pictures: the same
    /// controllers, with staged data, reading and writing nothing of the user's.
    /// SPEC: docs/spec.md — "Onboarding", the module preview.
    init(preview: Bool = false) {
        keepAwake = preview ? KeepAwakeController(demo: true) : KeepAwakeController()
        stats = SystemStatsController(demo: preview)
        clipboard = ClipboardController(demo: preview)
        tracker = TrackerController(demo: preview)
        todos = TodosController(demo: preview)
        vpn = VPNController(demo: preview)
        appShelves = AppShelvesController(demo: preview)
        colorPicker = ColorPickerController(clipboard: clipboard)
        screenText = ScreenTextController(clipboard: clipboard)
        if preview {
            // Staged rows for the pictures: an empty tracker and an empty list
            // show a heading and nothing else. The sample names are translated
            // like any other string.
            let lang = L10n.current
            let a = L10n.t(.onbSampleTaskA, lang)
            let b = L10n.t(.onbSampleTaskB, lang)
            todos.add(text: a)
            todos.add(text: b)
            let track = tracker.engine.addTask(name: L10n.t(.onbSampleTrackA, lang))
            _ = tracker.engine.addSession(taskID: track, seconds: 42 * 60)
            let second = tracker.engine.addTask(name: L10n.t(.onbSampleTrackB, lang))
            _ = tracker.engine.addSession(taskID: second, seconds: 15 * 60)
            screenText.loadDemo(L10n.t(.onbSampleOcr, lang))
            converter.batch.images = [
                .init(url: URL(fileURLWithPath: "/Users/preview/Pictures/cover.heic"), bytes: 4_182_000),
                .init(url: URL(fileURLWithPath: "/Users/preview/Pictures/poster.png"), bytes: 2_640_000),
            ]
        }
        // a finished recognition brings its window forward: the text has to be
        // visible, not just quietly filed away
        screenText.onResult = { [weak self] in self?.openScreenTextWindow?() }
        Self.sharedKeepAwake = keepAwake
        forwarders.append(engine.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        forwarders.append(keepAwake.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        forwarders.append(updater.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        forwarders.append(converter.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        forwarders.append(speedTest.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        forwarders.append(torrent.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        forwarders.append(tracker.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        forwarders.append(todos.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        forwarders.append(colorPicker.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        forwarders.append(screenText.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        forwarders.append(archive.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        forwarders.append(keyboardLock.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        // the helper download drives the archive rows' progress text
        forwarders.append(archive.helper.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        // a conversion starting or finishing counts as active use ("copy-paste"):
        // dropFirst skips the value the subscription replays at init, so launch
        // itself doesn't look like an interaction
        forwarders.append(converter.$busy.dropFirst().sink { [weak self] _ in
            self?.activity.note()
        })
        engine.onFinish = {
            MediaPauser.pauseIfEnabled() // silence first, then our alert
            // the finish sound plays EXACTLY ONCE — no repeat timer. The blink
            // (bell + digits) carries the "still finished" cue until the panel
            // is opened (acknowledged), reset, or a new start.
            Alerts.fire(mode: AlertMode.current)
        }
        engine.onPhaseChange = { nextIsWork in
            let lang = L10n.current
            Alerts.fire(
                mode: AlertMode.current,
                title: L10n.t(nextIsWork ? .workLabel : .restLabel, lang)
            )
        }
    }

    /// Alarm-blink phase for the finished state: true means "lit". This is the
    /// urgent PRE-acknowledge blink (full on/off). Once the finish is acknowledged
    /// (the panel was opened) the alarm blink settles to steady lit, so this
    /// returns true whenever the engine is no longer blinking. The gentle
    /// post-acknowledge pulse lives in `finishedPulseOpacity`.
    var blinkOn: Bool {
        guard engine.isFinishBlinking else { return true }
        return Int(engine.heartbeat.timeIntervalSinceReferenceDate * 2) % 2 == 0
    }

    /// Dim level for the calm post-acknowledge finished pulse — subtle enough to
    /// read as a breath, never a full disappear.
    private static let finishedPulseDim: Double = 0.4

    /// Opacity for the zeroed digits' calm pulse AFTER the finish is acknowledged:
    /// the alarm blink and the bell are gone, but the digits keep dimming and
    /// returning as a "finished — reset me" cue until the timer is reset or
    /// restarted. Tick-driven off the engine heartbeat (never a `repeatForever`
    /// animation, which would break the popover sizing); 1.0 everywhere else, so
    /// it never touches the running countdown or the pre-acknowledge alarm blink.
    var finishedPulseOpacity: Double {
        guard engine.isFinishSettled else { return 1 }
        let lit = Int(engine.heartbeat.timeIntervalSinceReferenceDate * 2) % 2 == 0
        return lit ? 1 : Self.finishedPulseDim
    }
}
