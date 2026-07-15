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
    private var statsCancellable: AnyCancellable?

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
        }

        // redraw the label on every state change (ticker, awake, settings)
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
        model.panelFocusChanged = { [weak self] in self?.maybeReturnFocus() }
        // once the panel closes, put the countdown back into the menu bar
        NotificationCenter.default.addObserver(
            forName: NSPopover.willCloseNotification, object: popover, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.frozenTitleLength = nil
                self?.frozenBarTimeVisible = nil
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
                self.realignPopover()
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
                        self.realignPopover()
                        self.panelOriginX = panelWindow.frame.origin.x
                    }
                } else {
                    self.panelOriginX = x
                }
            }
        }
        applyTheme()
        refreshButton()
    }

    /// Menu bar title length, frozen while the panel is open
    /// (nil — panel closed, width is free to change).
    private var frozenTitleLength: Int?

    /// Whether the bar showed the time when the panel opened (nil — closed).
    /// The PRESENCE is frozen too: a countdown appearing mid-session would
    /// resize the button and drag the attached panel with it.
    private var frozenBarTimeVisible: Bool?

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
    private func realignPopover() {
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

    private func togglePopover(opening tab: PanelView.Tab? = nil) {
        if let tab {
            model.openTab = tab
        }
        if popover.isShown {
            if tab == nil { popover.close() }
            return
        }
        guard let button = statusItem.button else { return }
        // freeze the button width while the panel is open: the countdown keeps
        // ticking (monospaced font), and on state changes the string is
        // padded with spaces to the same length — geometry stays constant,
        // so there is simply nothing to make the panel drift
        frozenTitleLength = button.attributedTitle.string.count
        frozenBarTimeVisible = !button.attributedTitle.string
            .trimmingCharacters(in: .whitespaces).isEmpty
        // windows left open (converter mid-batch etc.) come back with the panel:
        // they sink behind other apps and clicking the star is how users return
        model.raiseOpenWindows?()
        presentPopover()
        refreshButton() // freeze the width immediately, without waiting for a tick
    }

    private func presentPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
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
        menu.addItem(item(L10n.t(.aboutTitle, lang).capitalizedFirst, #selector(menuOpenAbout)))
        menu.addItem(item(L10n.t(.settingsTitle, lang).capitalizedFirst, #selector(menuOpenSettings)))
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

    @objc private func menuOpenPanel() { togglePopover(opening: .timer) }
    @objc private func menuOpenAbout() { model.openAboutWindow?() }
    @objc private func menuOpenSettings() { model.openSettingsWindow?() }
    @objc private func menuQuit() { model.requestQuit?() }
    @objc private func menuStopEngine() { model.engine.reset() }
    @objc private func menuDisableAwake() { model.keepAwake.deactivate() }

    // MARK: - Label

    func refreshButton() {
        guard let button = statusItem.button else { return }
        let engine = model.engine
        let state = engine.state
        let finished = state == .finished
        let badge: MenuBarIcon.StateBadge? = {
            switch state {
            case .running: return .running
            case .paused: return .paused
            case .idle, .finished: return nil
            }
        }()
        let bellOn = Int(engine.heartbeat.timeIntervalSinceReferenceDate * 2) % 2 == 0
        let bell = bellOn ? "bell.fill" : "bell"

        let showCountdown = UserDefaults.standard
            .object(forKey: SettingsKey.showMenuBarCountdown) as? Bool ?? true
        // the play/pause badge is redundant when the countdown is visible in the menu bar:
        // the digits themselves say the timer is running
        let countdownVisible = showCountdown && (state == .running || state == .paused)
        let effectiveBadge = countdownVisible ? nil : badge
        // red "!" — only if enabled in the monitor settings.
        // debugRedBadgeAlways — temporary mode for polishing the appearance:
        // defaults write com.antonshakirov.minimo debugRedBadgeAlways -bool true
        let alertMark = (UserDefaults.standard.bool(forKey: SettingsKey.menuBarRedAlert)
            && model.stats.redZone)
            || UserDefaults.standard.bool(forKey: "debugRedBadgeAlways")
        // dot: yellow — keep-awake (takes priority); orange — lid only
        let awakeDotColor: NSColor? = model.keepAwake.isActive
            ? .systemYellow
            : (model.keepAwake.lidApplied ? .systemOrange : nil)

        if effectiveBadge != nil || awakeDotColor != nil || alertMark {
            button.image = MenuBarIcon.compose(
                base: finished ? .symbol(bell) : .dial,
                badge: effectiveBadge,
                awakeDot: awakeDotColor,
                alertMark: alertMark
            )
        } else if finished {
            button.image = MenuBarIcon.compose(base: .symbol(bell), badge: nil, awakeDot: nil)
        } else {
            button.image = MenuBarIcon.dialTemplate
        }
        button.imagePosition = .imageLeft

        // monospaced font: the width doesn't jump as digits change
        var title = ""
        if showCountdown, state == .running || state == .paused {
            let value = engine.isStopwatch ? engine.elapsed : engine.remaining
            title = " " + TimeFormatting.short(value)
        } else if showCountdown, frozenBarTimeVisible == true {
            // digits were visible when the panel opened: a reset must not blank
            // the bar mid-session — show the reset value until the panel closes
            title = " " + TimeFormatting.short(engine.isStopwatch ? engine.elapsed : engine.duration)
        }
        // presence freeze: the bar was empty when the panel opened — a timer
        // started from the panel must not surface the label until close
        if frozenBarTimeVisible == false {
            title = ""
        }
        if let frozen = frozenTitleLength {
            // panel open: the time STAYS visible in the menu bar (Anton,
            // 2026-07-15) — only the width is frozen: pad with spaces to the
            // frozen length so the button and the attached panel don't move.
            // If the digits outgrow the slot (stopwatch passing an hour),
            // extend the freeze — the didMove observer re-anchors the panel.
            if title.count > frozen {
                frozenTitleLength = title.count
            } else {
                title += String(repeating: " ", count: frozen - title.count)
            }
        }
        if title.isEmpty {
            button.title = ""
        } else {
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
            )
        }

        // the anchor is fixed to the icon zone — no re-anchoring needed at all:
        // the icon is always on the left, the countdown grows on the right and never touches the anchor
    }
}
