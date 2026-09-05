import AppKit
import Combine
import SwiftUI
import HopCore

/// Rounds the preferred size up to whole points: fractional SwiftUI text
/// heights otherwise land the popover frame on a half pixel and the whole
/// panel (most visibly the header icons) jiggles 1px between tabs.
@MainActor
private final class IntegralSizeHostingController: NSHostingController<AnyView> {
    override var preferredContentSize: NSSize {
        get { super.preferredContentSize }
        set {
            super.preferredContentSize = NSSize(
                width: newValue.width.rounded(.up),
                height: newValue.height.rounded(.up)
            )
        }
    }
}

/// Native status item: left click shows the popover with the panel,
/// right click shows the context menu (open / about / settings / quit).
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?
    /// Redraws the icon when the menu bar's appearance changes under it.
    private var appearanceObserver: NSKeyValueObservation?
    private var statsCancellable: AnyCancellable?
    /// Runs only across a handover between two clocks sharing the bar.
    private var fadeTicker: Timer?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.animates = false
        // top alignment: with the height rounded up, the sub-point leftover
        // goes to the bottom edge instead of re-centering the content
        let host = IntegralSizeHostingController(rootView: AnyView(
            PanelView().environmentObject(model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .hopLayoutDirection()
        ))
        // preferredContentSize: the popover tracks the SwiftUI content size
        // without animating the first recalculation (fixes the shifted first click on monitor)
        host.sizingOptions = .preferredContentSize
        // no size animation: switching tabs doesn't "slide" from bottom to top
        popover.animates = false
        host.view.layoutSubtreeIfNeeded()
        popover.contentViewController = host
        popover.contentSize = Self.integral(host.view.fittingSize)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // A decorated icon is a bitmap, so it has to be redrawn when the bar
            // changes colour under it — switching to a full-screen window with
            // the other appearance, or the system flipping at sunset.
            appearanceObserver = button.observe(\.effectiveAppearance, options: [.new]) {
                [weak self] _, _ in
                Task { @MainActor in self?.refreshButton() }
            }
        }

        // redraw the label on every state change (timer/tracker heartbeat,
        // awake, settings). AppModel already forwards tracker.objectWillChange
        // — both its $heartbeat and the engine's changes — into this stream, so
        // the stopwatch tracking badge toggles on start/stop and the bar time
        // ticks 1/s without a separate subscription here.
        cancellable = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshButton() }
        // the monitor's red zone is refreshed by the background stats tick
        statsCancellable = model.stats.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshButton() }
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshButton()
                self?.applyTheme()
            }
        }
        model.closePanel = { [weak self] in self?.popover.close() }
        model.reopenPanel = { [weak self] screen in
            guard let self, !self.popover.isShown else { return }
            self.togglePopover(opening: screen)
        }
        // the updater treats an open panel as active use and won't relaunch under it
        model.isPanelOpen = { [weak self] in self?.popover.isShown ?? false }
        model.panelFocusChanged = { [weak self] in self?.maybeReturnFocus() }
        // belt and suspenders: click pings cover most paths, but ANY way Hop
        // becomes the active app while the panel is open (tab switches,
        // scrolls, AppKit quirks) must also hand the keyboard back — voice
        // tools and dictation target whichever app is frontmost
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popover.isShown else { return }
                // let the click that activated us finish first: focus fields
                // and editUnit update on the same runloop turn
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    // The app was re-activated by clicking one of its OWN real
                    // windows (settings/about/converter/…) — that window is now
                    // key. The panel is a transient popover: it must not stay
                    // glued on its elevated level above the clicked window, or
                    // it resurfaces there on the next activation. Close it, just
                    // as an outside click does. A genuine summon yields activation
                    // back to the previous app first, so the key window is nil (or
                    // the panel itself) here and the panel is kept (Anton, 2026-07-19).
                    let panelWindow = self.popover.contentViewController?.view.window
                    if let key = NSApp.keyWindow, key !== panelWindow {
                        self.popover.close()
                        return
                    }
                    self.maybeReturnFocus()
                }
            }
        }
        // once the panel closes, put the countdown back into the menu bar
        NotificationCenter.default.addObserver(
            forName: NSPopover.willCloseNotification, object: popover, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // closing the panel starts the idle countdown for the updater
                self?.model.activity.note()
                self?.frozenTitleLength = nil
                self?.frozenSlots = nil
                self?.panelOriginX = nil
                self?.hiddenAnchorWindow?.orderOut(nil)
                self?.hiddenAnchorWindow = nil
                self?.previousApp = nil
                self?.model.panelKeyboardCaptured = false
                self?.refreshButton()
            }
        }
        // the button shrinks/grows (countdown) → its WINDOW shifts along the menu bar,
        // while the popover stays at the old coordinates; catch the move and re-anchor
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, let button = self.statusItem.button,
                      (note.object as? NSWindow) === button.window else { return }
                self.realignPopover(reason: "realign-btn")
            }
        }
        // growing content (expanded clipboard) → AppKit recalculates the popover and
        // may lose the custom positioningRect, re-centering the arrow
        // on the whole button — the panel drifts sideways. Re-attach the anchor ONLY
        // on a real horizontal drift: unconditionally re-anchoring on every
        // resize made the panel jitter vertically during normal downward growth
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, self.popover.isShown,
                      let panelWindow = self.popover.contentViewController?.view.window,
                      (note.object as? NSWindow) === panelWindow else { return }
                let x = panelWindow.frame.origin.x
                if let known = self.panelOriginX {
                    if abs(known - x) > 0.5 {
                        self.realignPopover(reason: "realign-h")
                        self.panelOriginX = panelWindow.frame.origin.x
                    }
                } else {
                    self.panelOriginX = x
                }
            }
        }
        // dev-only: raw frame diagnostics for the panel-hop investigation
        // (debugPanelFrameLog flag, see debugLogPanelFrame below) — catches
        // every geometry change AppKit reports for the panel window, on top
        // of whatever the handlers above choose to act on
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self,
                      let panelWindow = self.popover.contentViewController?.view.window,
                      (note.object as? NSWindow) === panelWindow else { return }
                self.debugLogPanelFrame("move", frame: panelWindow.frame)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self,
                      let panelWindow = self.popover.contentViewController?.view.window,
                      (note.object as? NSWindow) === panelWindow else { return }
                self.debugLogPanelFrame("resize", frame: panelWindow.frame)
            }
        }
        applyTheme()
        refreshButton()
    }

    /// Menu bar title length, frozen while the panel is open
    /// (nil — panel closed, width is free to change).
    private var frozenTitleLength: Int?

    /// Which clocks the bar was showing when the panel opened (nil — closed).
    /// The SET is frozen, not just the width: a reading appearing mid-session
    /// would resize the button and drag the attached panel with it, and a
    /// reading VANISHING would leave the space it was padded to standing empty
    /// (Anton, 2026-08-04). A stopped timer keeps its slot and shows what it
    /// stopped at until the panel is closed.
    private var frozenSlots: [BarSlot]?

    /// A clock with something to say in the bar. The tracked task carries its
    /// identity, so its figure survives the task being stopped.
    private enum BarSlot: Equatable {
        case engine
        case tracker(UUID)
    }

    /// Whole-point size: a fractional SwiftUI height lands the popover
    /// frame on a half pixel and the panel content jiggles 1px between tabs.
    private static func integral(_ size: NSSize) -> NSSize {
        NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    /// Reference X of the panel window: a change during resize = lost anchor.
    private var panelOriginX: CGFloat?

    /// The app that was frontmost when the panel opened: the panel is
    /// keyboard-transparent, so focus keeps going back to that app.
    private var previousApp: NSRunningApplication?

    /// Give the keyboard back to the app under the panel — unless the panel
    /// is actually typing (digit entry, the clipboard search field) or focus
    /// has legitimately moved to another Hop window (settings, converter).
    func maybeReturnFocus() {
        guard popover.isShown else { return }
        guard !model.panelKeyboardCaptured else { return }
        let panelWindow = popover.contentViewController?.view.window
        if let key = NSApp.keyWindow, key !== panelWindow { return }
        // a focused text field (field editor) means real typing — keep it
        if let responder = panelWindow?.firstResponder, responder is NSText { return }
        guard let previousApp, !previousApp.isTerminated,
              previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        NSApp.yieldActivation(to: previousApp)
        previousApp.activate()
    }

    /// Re-anchor to the current geometry: NSPopover ignores an identical
    /// positioningRect, so nudge it half a pixel and set it back.
    /// - Parameter reason: which caller triggered the realign — "realign-btn"
    ///   (status button moved) or "realign-h" (panel drifted horizontally on
    ///   resize) — used only to tag the debugPanelFrameLog line below.
    private func realignPopover(reason: String) {
        if let panelWindow = popover.contentViewController?.view.window {
            debugLogPanelFrame(reason, frame: panelWindow.frame)
        }
        // detached mode (icon hidden by a menu bar manager): the anchor is
        // a stub window at the screen's top-right corner, nothing to re-pin
        guard hiddenAnchorWindow == nil else { return }
        guard popover.isShown, let button = statusItem.button else { return }
        var nudge = Self.iconAnchor(button)
        nudge.size.width += 0.5
        popover.positioningRect = nudge
        popover.positioningRect = Self.iconAnchor(button)
    }

    /// Icon zone within the status item button: the popover arrow always points at the star.
    private static func iconAnchor(_ button: NSStatusBarButton) -> NSRect {
        // the exact image frame from the cell — dead-center at any padding
        // and title width; fixed 28pt drifted when the insets changed
        if let cell = button.cell as? NSButtonCell {
            let rect = cell.imageRect(forBounds: button.bounds)
            if rect.width > 0 { return rect }
        }
        return NSRect(x: 0, y: 0, width: 28, height: button.bounds.height)
    }

    /// true when the status item is actually visible in the menu bar.
    /// Menu bar managers (Ice, Bartender, Hidden Bar) hide items by
    /// collapsing them to zero width or moving their window off-screen.
    private static func buttonIsVisible(_ button: NSStatusBarButton) -> Bool {
        guard let window = button.window, window.frame.width > 1 else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(window.frame) }
    }

    /// Invisible 2×2 stub at the top-right of the screen: when the icon is
    /// hidden, the popover attaches here instead of macOS clamping it
    /// into the top-LEFT corner (the anchor rect of an off-screen button
    /// degenerates to zero).
    private var hiddenAnchorWindow: NSWindow?

    private func showPopoverDetached() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let rect = NSRect(x: frame.maxX - 44, y: frame.maxY - 2, width: 2, height: 2)
        let anchor = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.hasShadow = false
        anchor.level = .statusBar
        anchor.ignoresMouseEvents = true
        anchor.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        anchor.orderFrontRegardless()
        hiddenAnchorWindow = anchor
        if let view = anchor.contentView {
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }

    /// The popover theme follows the settings / system choice.
    func applyTheme() {
        popover.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
    }

    // MARK: - Clicks

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    /// For the global hotkey.
    func togglePanel() {
        togglePopover()
    }

    private func togglePopover(opening screen: PanelView.InitialScreen? = nil) {
        // Reaching for Hop while the keyboard is locked IS the way out: the mark
        // in the menu bar says why the keys do nothing, and opening the panel
        // lets go of them (Anton, 2026-07-25). The unlock plays its own cue.
        if model.keyboardLock.isLocked {
            model.keyboardLock.unlock()
        }
        if let screen {
            model.openTab = screen
        }
        if popover.isShown {
            if screen == nil { popover.close() }
            return
        }
        guard let button = statusItem.button else { return }
        // freeze the button width while the panel is open: the countdown keeps
        // ticking (monospaced font), and on state changes the string is
        // padded with spaces to the same length — geometry stays constant,
        // so there is simply nothing to make the panel drift
        frozenTitleLength = button.attributedTitle.string.count
        // Whether the TIMER time was showing — decided from the timer state, NOT
        // from "is the title non-empty": the torrent glance arrow (↓/↑) also fills
        // the title, and treating that as "time visible" wrongly surfaced the
        // countdown while the timer was off, which shifted the panel on open.
        frozenSlots = currentSlots()
        // windows left open (converter mid-batch etc.) come back with the panel:
        // they sink behind other apps and clicking the star is how users return
        model.raiseOpenWindows?()
        presentPopover()
        refreshButton() // freeze the width immediately, without waiting for a tick
    }

    private func presentPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        model.activity.note() // opening the panel is active use
        // opening the panel acknowledges a finished timer: the bar bell and the
        // digits stop blinking and settle steady (the state stays finished).
        model.engine.acknowledgeFinish()

        // the app that was frontmost before the icon click: we give focus back
        // to it so system dictation/paste go there, not into the panel
        previousApp = NSWorkspace.shared.frontmostApplication
        // pin the content size BEFORE showing: if NSPopover refines the size
        // after appearing, it re-centers itself — the panel jerks sideways
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            popover.contentSize = Self.integral(view.fittingSize)
        }
        // anchor to the ICON zone, not the whole button: when the countdown
        // appears the button grows, and a full-bounds popover drifted away from the star.
        // icon hidden by a menu bar manager → the panel opens at the
        // top-right corner instead of being squeezed into the top-left
        if Self.buttonIsVisible(button) {
            popover.show(relativeTo: Self.iconAnchor(button), of: button, preferredEdge: .minY)
        } else {
            showPopoverDetached()
        }
        if let panelWindow = popover.contentViewController?.view.window {
            debugLogPanelFrame("shown", frame: panelWindow.frame)
        }
        // return focus to the previous app: the panel stays visible
        // (transient doesn't close on programmatic activation), and the keyboard
        // is back with that app. Clicking inside the panel refocuses it — digit input still works
        if let previousApp,
           previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate()
        }
        // do NOT grab the keyboard on open: dictation and Cmd+V must keep
        // flowing into the app underneath. The panel becomes key on its own
        // when the user clicks its input field/display
        panelOriginX = popover.contentViewController?.view.window?.frame.origin.x
    }

    private func showContextMenu() {
        let lang = L10n.current
        let menu = NSMenu()
        menu.applyHopLayoutDirection()
        // system menu uses capitalized items: lowercase here reads as
        // a mistake, not a style (the signature lowercase lives inside the panel)

        // everything "dynamic" can be stopped right from the menu: a running
        // timer/stopwatch and keep-awake — without opening the panel
        let engineState = model.engine.state
        if engineState == .running || engineState == .paused {
            let key: L10nKey = model.engine.isStopwatch ? .menuStopStopwatch : .menuStopTimer
            menu.addItem(item(L10n.t(key, lang).capitalizedFirst, #selector(menuStopEngine)))
        }
        if model.keepAwake.isActive {
            menu.addItem(item(L10n.t(.menuDisableAwake, lang).capitalizedFirst, #selector(menuDisableAwake)))
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }

        menu.addItem(item(L10n.t(.menuOpen, lang).capitalizedFirst, #selector(menuOpenPanel)))
        menu.addItem(item(L10n.t(.settingsTitle, lang).capitalizedFirst, #selector(menuOpenSettings)))
        // the same words the sidebar uses for those two pages: one screen, one name
        menu.addItem(item(L10n.t(.guideTab, lang).capitalizedFirst, #selector(menuOpenGuide)))
        menu.addItem(item(L10n.t(.aboutTitle, lang).capitalizedFirst, #selector(menuOpenAbout)))
        menu.addItem(.separator())
        menu.addItem(item(L10n.t(.menuQuit, lang).capitalizedFirst, #selector(menuQuit)))

        // NSStatusItem trick: the menu is assigned only for the duration of the click,
        // otherwise it would intercept left clicks too
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func menuOpenPanel() { togglePopover(opening: .spaceContaining("timer")) }
    @objc private func menuOpenSettings() { model.openSettingsWindow?() }
    @objc private func menuOpenGuide() { openSettings(at: .guide) }
    @objc private func menuOpenAbout() { openSettings(at: .about) }

    private func openSettings(at section: SettingsSelection) {
        model.settingsSectionRequest = section.id
        model.openSettingsWindow?()
    }
    @objc private func menuQuit() { model.requestQuit?() }
    @objc private func menuStopEngine() { model.engine.reset() }
    @objc private func menuDisableAwake() { model.keepAwake.deactivate() }

    // MARK: - Label

    func refreshButton() {
        guard let button = statusItem.button else { return }
        // SPEC: docs/spec.md — "A module that is off is off everywhere".
        let off = ModuleActivation.inactiveModules()
        let timerOn = !off.contains("timer")

        let engine = model.engine
        let state = engine.state
        let finished = state == .finished && timerOn
        // the bell blinks only while the finish is unacknowledged; once the
        // panel is opened it settles to the steady lit bell (calm-down).
        let bellOn = !engine.isFinishBlinking
            || Int(engine.heartbeat.timeIntervalSinceReferenceDate * 2) % 2 == 0
        let bell = bellOn ? "bell.fill" : "bell"

        let showCountdown = UserDefaults.standard
            .object(forKey: SettingsKey.showMenuBarCountdown) as? Bool ?? true
        // engine → the single running/paused/idle slot; the digits, when shown,
        // carry the running value so the green wedge would only duplicate them
        let engineSlot: IconState.Engine = {
            guard timerOn else { return .idle }
            switch state {
            case .running: return .running
            case .paused: return .paused
            case .idle, .finished: return .idle
            }
        }()
        let engineTimeInTitle = timerOn && showCountdown && (state == .running || state == .paused)

        let tracking = model.tracker.isTracking && !off.contains("tracker")
        // the task's ticking "today" figure is in the TITLE whenever it is opted
        // in: a countdown beside it no longer takes the slot away, the two share
        // it in turns, so the badge stays out of the way either way
        let taskTimeInTitle = tracking
            && UserDefaults.standard.bool(forKey: SettingsKey.trackerTimeInBar)

        // steady "!" — the monitor red zone (opt-in). debugRedBadgeAlways forces
        // it on for polishing: defaults write com.antonshakirov.minimo debugRedBadgeAlways -bool true
        let alertSteady = (UserDefaults.standard.bool(forKey: SettingsKey.menuBarRedAlert)
            && model.stats.redZone
            && !off.contains("system"))
            || UserDefaults.standard.bool(forKey: "debugRedBadgeAlways")
        // blinking "!" — a task left running past 8h (the same episode logic as
        // the panel banner: respects THIS run's acknowledgment, stored by the
        // panel under this same UserDefaults key)
        let ackRaw = UserDefaults.standard.double(forKey: "trackerOverrunAckStart")
        let ack = ackRaw == 0 ? nil : Date(timeIntervalSinceReferenceDate: ackRaw)
        let alertBlinking = tracking && TrackerOverrun.isBannerVisible(
            activeStart: model.tracker.engine.activeIntervalStart,
            now: model.tracker.heartbeat, acknowledged: ack)
        // 1s-on / 1s-off blink driven by the tracker's per-second heartbeat
        let blinkOn = Int(model.tracker.heartbeat.timeIntervalSinceReferenceDate) % 2 == 0

        let transfer = off.contains("torrent") ? (down: false, up: false)
            : model.torrent.menuBarTransfer

        let colored = UserDefaults.standard
            .object(forKey: SettingsKey.coloredIndicators) as? Bool ?? true

        // A reminder that fired while nobody was looking. Unlike every other
        // badge this one has an off switch — it reports a user event rather than
        // an app state, so it belongs to the reminder signal settings.
        let reminderUnseen = model.todos.list.hasUnseenFiring
            && UserDefaults.standard.bool(forKey: SettingsKey.todoRemindMark)
            && !off.contains("todos")

        // The tunnel's own mark, which can be switched off: a VPN somebody else's
        // app holds up is not necessarily something the user wants reported. A
        // HIDDEN module carries its mark away with it — the badge is the module's
        // voice in the menu bar, and a module that is not on any space has no
        // business talking (Anton, 2026-07-29). Hiding does not touch the switch,
        // so bringing the module back brings the mark back with it.
        let vpnMark = UserDefaults.standard.bool(forKey: SettingsKey.vpnMenuBarMark)
            && !off.contains("vpn")

        let composition = IconBadges.compose(IconState(
            engine: engineSlot,
            engineTimeInTitle: engineTimeInTitle,
            tracking: tracking,
            taskTimeInTitle: taskTimeInTitle,
            noSleep: model.keepAwake.isActive && !off.contains("awake"),
            lid: model.keepAwake.lidApplied && !off.contains("awake"),
            alertSteady: alertSteady,
            alertBlinking: alertBlinking,
            blinkOn: blinkOn,
            reminderUnseen: reminderUnseen,
            vpn: vpnMark ? model.vpn.mark : nil,
            torrentDown: transfer.down,
            torrentUp: transfer.up,
            colored: colored
        ))

        // A locked keyboard REPLACES the star with a keyboard glyph: the keys
        // doing nothing needs an unmistakable explanation in the menu bar, and a
        // corner dot would be too quiet for a state that stops the whole
        // keyboard (Anton, 2026-07-25). It outranks the finished bell — the
        // timer can wait, a locked keyboard cannot.
        let keyboardLocked = model.keyboardLock.isLocked
        // The BUTTON's own appearance, not the app's: the menu bar can be dark
        // while the app is light — over a full-screen window, or the moment the
        // system switches — and a decorated icon is a bitmap with its colour
        // baked in. Reading NSApp meant the icon kept the colour of whatever the
        // bar looked like when it was last drawn, and went invisible on the other
        // one (Anton, 2026-07-29). The countdown next to it never had the problem:
        // AppKit colours a title itself.
        let barIsDark = button.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) != .aqua
        // template fast path ONLY when the calm star carries no decoration at all
        if keyboardLocked {
            button.image = MenuBarIcon.compose(composition, base: .symbol("keyboard.fill"),
                                               dark: barIsDark)
        } else if !composition.isEmpty {
            button.image = MenuBarIcon.compose(composition, base: finished ? .symbol(bell) : .dial,
                                               dark: barIsDark)
        } else if finished {
            button.image = MenuBarIcon.compose(composition, base: .symbol(bell), dark: barIsDark)
        } else {
            button.image = MenuBarIcon.dialTemplate
        }
        button.imagePosition = .imageLeft

        // Every clock that has something to say. The engine's countdown and the
        // tracked task's running total used to compete for the one slot, and the
        // countdown always won, so a task tracked under a running timer was
        // invisible in the bar. They take turns now (Anton, 2026-08-04).
        // While the panel is open the SET of readings is whatever it was when
        // the panel opened: a clock started from the panel must not surface
        // mid-session, and one stopped from the panel must not disappear and
        // leave its padded space empty. The figures themselves stay live.
        let readings = (frozenSlots ?? currentSlots()).map(reading(for:))

        // monospaced font: the width doesn't jump as digits change
        var title = ""
        var glyph: String?
        var opacity: Double = 1
        if readings.count > 1 {
            // whose turn it is, and how far through a handover we are — both
            // read off the clock, so any redraw lands on the same answer
            let now = Date()
            let reading = readings[MenuBarCycle.index(count: readings.count, now: now)]
            title = " " + reading.text
            // While the panel is open the status item is HIGHLIGHTED, and AppKit
            // inverts a title it colours itself. Ours it would not, so the
            // rotation shows its bare digits for as long as the panel is up —
            // nobody is reading the menu bar while looking at the panel anyway.
            if !popover.isShown {
                glyph = reading.symbol
                // quantised: the fade is drawn from a bounded set of tints, which
                // is what lets the tinted glyphs be cached across a handover
                opacity = (MenuBarCycle.opacity(now: now) * 20).rounded() / 20
                scheduleFadeTick(from: now)
            }
        } else if let reading = readings.first {
            // one clock speaking needs no glyph: this is the bar as it has
            // always looked, and a lone number is not ambiguous
            title = " " + reading.text
        }
        // Torrent transfer moved OUT of the title into the icon's bottom-left
        // corner (↓/↑ arrows) — it no longer contributes any characters here, so
        // the title width is invariant to it and can never shift the panel. The
        // title now carries digits only (countdown or the opt-in tracker time).
        if let frozen = frozenTitleLength {
            // panel open: the time STAYS visible in the menu bar (Anton,
            // 2026-07-15) — only the width is frozen: pad the digit tail with
            // spaces to the frozen length so the button and the attached panel
            // don't move. If the total outgrows the frozen slot (the stopwatch
            // passes an hour) the freeze extends and the didMove observer
            // re-anchors; growth is always on the RIGHT, so the icon anchor
            // never moves.
            let total = title.count
            if total > frozen {
                frozenTitleLength = total
            } else {
                title += String(repeating: " ", count: frozen - total)
            }
        }
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        if title.isEmpty {
            button.title = ""
        } else {
            button.attributedTitle = Self.barLabel(
                title, glyph: glyph, opacity: opacity,
                appearance: button.effectiveAppearance, font: mono)
        }

        // the anchor is fixed to the icon zone — no re-anchoring needed at all:
        // the icon is always on the left, the countdown grows on the right and never touches the anchor
    }

    /// The clocks with something to say right now.
    private func currentSlots() -> [BarSlot] {
        var slots: [BarSlot] = []
        let off = ModuleActivation.inactiveModules()
        let showCountdown = UserDefaults.standard
            .object(forKey: SettingsKey.showMenuBarCountdown) as? Bool ?? true
        let state = model.engine.state
        if showCountdown, !off.contains("timer"), state == .running || state == .paused {
            slots.append(.engine)
        }
        // the tracked task's ticking "today" value, opt-in
        if model.tracker.isTracking,
           !off.contains("tracker"),
           UserDefaults.standard.bool(forKey: SettingsKey.trackerTimeInBar),
           let activeID = model.tracker.engine.activeTaskID {
            slots.append(.tracker(activeID))
        }
        return slots
    }

    /// What a slot reads at this instant. A stopped timer shows what it is set
    /// to, a stopped task the total it reached — never a blank.
    private func reading(for slot: BarSlot) -> (symbol: String, text: String) {
        switch slot {
        case .engine:
            let engine = model.engine
            let running = engine.state == .running || engine.state == .paused
            let value: TimeInterval
            if engine.isStopwatch {
                value = engine.elapsed
            } else {
                value = running ? engine.remaining : engine.duration
            }
            return (engine.isStopwatch ? "stopwatch" : "timer", TimeFormatting.short(value))
        case .tracker(let id):
            return ("record.circle", TimeFormatting.short(model.tracker.engine.today(taskID: id)))
        }
    }

    // MARK: - Taking turns

    /// A fine tick for the length of one handover, and not a moment longer. The
    /// label otherwise redraws once a second off the heartbeat, which would turn
    /// the fade into three frames; a menu-bar app that woke up twenty times a
    /// second all day to keep a fade smooth would be a worse trade.
    private func scheduleFadeTick(from now: Date) {
        guard fadeTicker == nil, MenuBarCycle.untilFade(now: now) <= 1 else { return }
        let ticker = Timer(timeInterval: 0.03, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                // the handover is over once the digits are fully legible again
                if MenuBarCycle.opacity(now: Date()) >= 1, MenuBarCycle.untilFade(now: Date()) > 0.5 {
                    timer.invalidate()
                    self.fadeTicker = nil
                }
                self.refreshButton()
            }
        }
        ticker.tolerance = 0.01
        RunLoop.main.add(ticker, forMode: .common)
        fadeTicker = ticker
    }

    /// The digits, with the glyph of whichever clock is speaking right in front
    /// of them: the gap goes BEFORE the glyph, so the pair reads as one thing
    /// and it is obvious which clock the number belongs to.
    ///
    /// Colour is taken over for the whole rotation rather than only for the
    /// fading frames. Handing it back to AppKit at full opacity meant the ink
    /// changed hands mid-fade, and that hand-off is exactly what read as a
    /// flicker. The colour used IS AppKit's own — `labelColor` resolved in the
    /// bar's appearance — so a label at rest looks the way it always did.
    private static func barLabel(
        _ text: String, glyph: String?, opacity: Double, appearance: NSAppearance, font: NSFont
    ) -> NSAttributedString {
        guard let glyph else {
            // one clock speaking: the label AppKit has always drawn, colour and all
            return NSAttributedString(string: text, attributes: [.font: font])
        }
        var ink = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            ink = NSColor.labelColor.usingColorSpace(.sRGB) ?? ink
        }
        let faded = ink.withAlphaComponent(ink.alphaComponent * max(0, min(1, opacity)))
        let label = NSMutableAttributedString()
        label.append(NSAttributedString(string: " ", attributes: [.font: font]))
        if let image = symbolImage(glyph, color: faded, pointSize: font.pointSize - 1.5) {
            let attachment = NSTextAttachment()
            attachment.image = image
            // sit the glyph on the text's own baseline rather than the line box
            attachment.bounds = NSRect(x: 0, y: font.descender + 1,
                                       width: image.size.width, height: image.size.height)
            label.append(NSAttributedString(attachment: attachment))
        }
        // a hair space: the number belongs to the glyph, not to the bar
        let digits = String(text.drop(while: { $0 == " " }))
        label.append(NSAttributedString(string: "\u{2009}" + digits,
                                        attributes: [.font: font, .foregroundColor: faded]))
        return label
    }

    /// An SF Symbol painted in one colour, the same way the icon's own glyphs
    /// are painted: a template image inside an attributed title is not tinted
    /// for us. Tinting means a bitmap per frame, and a fade asks for one every
    /// 30 ms, so the results are kept — a handover reuses the same twenty.
    private static var symbolCache: [String: NSImage] = [:]

    private static func symbolImage(
        _ name: String, color: NSColor, pointSize: CGFloat
    ) -> NSImage? {
        let key = "\(name)|\(pointSize)|\(color.description)"
        if let cached = symbolCache[key] { return cached }
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
        else { return nil }
        let tinted = NSImage(size: base.size)
        tinted.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: base.size),
                  from: .zero, operation: .sourceOver, fraction: 1)
        color.set()
        NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        // the cache is keyed by colour, and a fade walks a bounded set of them;
        // a lifetime of appearance flips could still grow it, so it is capped
        if symbolCache.count > 200 { symbolCache.removeAll() }
        symbolCache[key] = tinted
        return tinted
    }

    // MARK: - Debug: panel frame log

    /// Dev-only diagnostics for the "panel hops on space switch" investigation:
    /// every frame AppKit reports for the popover panel window (move/resize/
    /// realign/show). `topEdge` is what must stay constant across a space switch;
    /// `origin`/`size` are AppKit's bottom-left coordinates. Routed through the
    /// shared `PanelFrameLog` sink so these window events and the SwiftUI chrome
    /// reader (task 8.18, tag `chromeY`) land on one timeline.
    private func debugLogPanelFrame(_ tag: String, frame: NSRect) {
        let topEdge = frame.origin.y + frame.height
        PanelFrameLog.write(tag, String(
            format: "x=%.2f y=%.2f w=%.2f h=%.2f top=%.2f",
            frame.origin.x, frame.origin.y, frame.width, frame.height, topEdge
        ))
    }
}

/// Shared dev-only sink for the panel-hop diagnostics: enable with
/// `defaults write <bundle id> debugPanelFrameLog -bool true` (same live-read
/// pattern as debugRedBadgeAlways), read via `UserDefaults.standard` so no
/// relaunch is needed. When on, each tagged line is appended to
/// `<Application Support>/<bundle id>/panel-frames.log` — the one thing that
/// can't be watched from outside the app, since macOS privacy blocks external
/// window observation. Both the window-frame observers (StatusItemController)
/// and the chrome global-minY reader (PanelView) write here, so window motion
/// and in-content chrome motion share a single timeline. Not `@MainActor`: the
/// file write is thread-agnostic and callers already run on the main thread.
enum PanelFrameLog {
    /// Cheap gate so the flag being off costs a single bool read (the `fields`
    /// autoclosure below is never evaluated when disabled).
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "debugPanelFrameLog") }

    static func write(_ tag: String, _ fields: @autoclosure () -> String) {
        guard enabled else { return }
        // systemUptime: monotonic seconds since boot, unaffected by clock changes
        let ms = ProcessInfo.processInfo.systemUptime * 1000
        let line = String(format: "%.3f %@ %@\n", ms, tag, fields())
        guard let data = line.data(using: .utf8) else { return }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.storageIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("panel-frames.log")
        if let handle = FileHandle(forWritingAtPath: file.path) {
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            // file doesn't exist yet: create it with this first line
            try? data.write(to: file)
        }
    }
}
