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

    /// Incremented on every theme change: .id(themeVersion) recreates views
    /// that SwiftUI would otherwise not redraw (their inputs did not change).
    @Published var themeVersion = 0

    /// Desired content height of the converter window (from the view's PreferenceKey).
    @Published var converterContentHeight: CGFloat = 0

    /// Request to open a specific screen (from the right-click menu).
    @Published var openTab: PanelView.Tab?
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
        engine.onFinish = { [weak self] in
            MediaPauser.pauseIfEnabled() // silence first, then our alert
            Alerts.fire(mode: AlertMode.current)
            self?.startAlarmRepeat()
        }
        engine.onPhaseChange = { nextIsWork in
            let lang = L10n.current
            Alerts.fire(
                mode: AlertMode.current,
                title: L10n.t(nextIsWork ? .workLabel : .restLabel, lang)
            )
        }
    }

    private var alarmTimer: Timer?

    /// The alert repeats while the display blinks the finished state; auto-mute on timeout.
    private func startAlarmRepeat() {
        alarmTimer?.invalidate()
        let cap = Sounds.alarmRepeatSeconds
        guard cap > 0, AlertMode.current != .silent else { return }
        let startedAt = Date()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let finished = self.engine.state == .finished
                let expired = Date().timeIntervalSince(startedAt) >= Double(cap)
                if !finished || expired {
                    timer.invalidate()
                    self.alarmTimer = nil
                } else {
                    Sounds.alarm()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        alarmTimer = timer
    }

    /// Blink phase for the finished state: true means "lit".
    var blinkOn: Bool {
        Int(engine.heartbeat.timeIntervalSinceReferenceDate * 2) % 2 == 0
    }
}
