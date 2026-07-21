import Combine
import Foundation
import HopCore

@MainActor
final class AppModel: ObservableObject {
    /// For emergency cleanup of awake on app exit.
    static var sharedKeepAwake: KeepAwakeController?

    let engine = TimerEngine()
    let keepAwake = KeepAwakeController()
    let stats = SystemStatsController()
    let clipboard = ClipboardController()
    let updater = UpdateChecker()
    let converter = FileConverter()
    let speedTest = SpeedTestController()
    let torrent = TorrentController()
    let tracker = TrackerController()
    let todos = TodosController()

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

    /// Request to open a specific screen (from the right-click menu).
    @Published var openTab: PanelView.InitialScreen?
    /// Close the popover (for "copy and paste").
    var closePanel: (() -> Void)?
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
    /// Open the standalone "about" window.
    var openAboutWindow: (() -> Void)?
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

    init() {
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
