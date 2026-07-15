import AppKit
import Combine
import SwiftUI
import HopCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // lazy: model initialization must not run before the crash-loop check —
    // in safe mode the model (and everything that could crash) is never created at all
    lazy var model = AppModel()
    private var safeStatusItem: NSStatusItem?
    private var safeUpdater: UpdateChecker?
    private var safeStatusSink: AnyCancellable?
    private var statusController: StatusItemController?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var converterWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var quitWindow: NSWindow?
    private var converterUserResized = false
    /// Content height we set on the window ourselves. A resize to any other
    /// height is a user action. A temporary flag did not work: didResize arrives
    /// asynchronously (queue .main + Task) after the flag is already reset, so
    /// auto-fit silently turned off forever — hence the "hole" below an empty converter
    private var converterExpectedHeight: CGFloat = -1
    private var contentHeightSink: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent without a Dock icon — including dev runs via `swift run`.
        NSApp.setActivationPolicy(.accessory)

        // crash-loop guard — BEFORE any modules: three unfinished launches in a row =
        // safe mode, where only the updater lives. Even a bug that crashes
        // startup cannot cut off the path to an update carrying the fix
        let crashLoop = LaunchGuard.registerLaunch()
        DispatchQueue.main.asyncAfter(deadline: .now() + LaunchGuard.stableAfter) {
            LaunchGuard.markStable()
        }
        if crashLoop {
            enterSafeMode()
            return
        }

        syncSystemTheme()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            // NOT via NSApp.delegate: with @NSApplicationDelegateAdaptor it holds
            // a SwiftUI wrapper, so the cast to AppDelegate silently failed — the
            // "auto" theme did not follow the system one
            Task { @MainActor in self?.syncSystemTheme() }
        }

        statusController = StatusItemController(model: model)

        let hotkeys = HotkeyManager.shared
        hotkeys.setHandler(.panel) { [weak self] in
            self?.statusController?.togglePanel()
        }
        hotkeys.setHandler(.timer) { [weak self] in
            self?.model.engine.toggle()
        }
        hotkeys.setHandler(.awake) { [weak self] in
            guard let awake = self?.model.keepAwake else { return }
        hotkeys.refreshSnapHotkeys() // window snap zones, if the toggle is on
            if awake.isActive {
                awake.deactivate()
            } else {
                awake.activate(KeepAwakeController.options.last!)
            }
        }

        let model = self.model
        model.updater.startAutoChecks { critical in
            let timerFree = model.engine.state == .idle || model.engine.state == .finished
            // a critical release ignores "don't disturb keep-awake" but never kills the timer
            return critical ? timerFree : (timerFree && !model.keepAwake.isActive)
        }

        model.openSettingsWindow = { [weak self] in
            self?.showSettingsWindow()
        }
        model.openConverterWindow = { [weak self] in
            self?.showConverterWindow()
        }
        model.openAboutWindow = { [weak self] in
            self?.showAboutWindow()
        }
        model.requestQuit = { [weak self] in
            self?.requestQuit()
        }
        model.raiseOpenWindows = { [weak self] in
            guard let self else { return }
            // miniaturized windows are not "visible": a deliberate minimize
            // stays in the Dock and is not yanked back.
            // orderFrontRegardless: plain orderFront only reorders within the
            // app's own layer while another app is active — the window came
            // back UNDER the frontmost app instead of on top with the panel
            for window in [converterWindow, settingsWindow, aboutWindow]
            where window?.isVisible == true {
                window?.orderFrontRegardless()
            }
        }
        AppIcon.apply() // Finder icon per the selected style
        model.refreshTheme = { [weak self] in
            self?.applyAppTheme()
        }
        WindowSnapController.shared.startTracking()

        // auto-height of the converter window from its content (until the user resizes it)
        // no removeDuplicates: on reopen the content height is the same,
        // and deduplication muted the fit — the window got stuck at the initial height.
        // adjustConverterHeight is idempotent (guard abs>2), so no loop
        contentHeightSink = model.$converterContentHeight
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.adjustConverterHeight() }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, let window = self.converterWindow,
                      (note.object as? NSWindow) === window else { return }
                let height = window.contentRect(forFrameRect: window.frame).height
                if abs(height - self.converterExpectedHeight) > 1 {
                    self.converterUserResized = true
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, (note.object as? NSWindow) === self.converterWindow else { return }
                self.converterUserResized = false // next open — auto again
            }
        }

        // temp diagnostics: open the converter without clicking the UI
        if CommandLine.arguments.contains("--open-about") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showAboutWindow()
                NSLog("HOP-DIAG about opened frame=%@", NSStringFromRect(self?.aboutWindow?.frame ?? .zero))
            }
        }
        if CommandLine.arguments.contains("--open-converter") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showConverterWindow()
                if let f = self?.converterWindow?.frame {
                    NSLog("HOP-DIAG converter frame=%@ visible=%d",
                          NSStringFromRect(f), (self?.converterWindow?.isVisible ?? false) ? 1 : 0)
                }
            }
        }

        if !UserDefaults.standard.bool(forKey: "onboardingDone") {
            showOnboarding()
        }
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
                // miniaturizable like the converter: settings can be sent to
                // the Dock instead of only closed
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // the window drags only by the title bar: background dragging
            // caught clicks on tabs and chips — the window moved when switching
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            let host = NSHostingController(
                rootView: PanelView(initialTab: .settings, standaloneSettings: true)
                    .environmentObject(model)
            )
            // same reliable path as about/converter: explicit size +
            // sizingOptions=[] so the hosting controller doesn't break AutoLayout with constraints
            host.sizingOptions = []
            window.contentViewController = host
            window.contentMinSize = NSSize(width: 640, height: 300)
            window.contentMaxSize = NSSize(width: 640, height: 100_000)
            // "latest version installed" must not survive the settings window:
            // an update may ship while it's closed and the note would lie
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.model.updater.clearTransientStatus() }
            }
            settingsWindow = window
        }
        guard let window = settingsWindow else { return }
        window.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        if !window.isVisible {
            let screenH = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
            window.setContentSize(NSSize(width: 640, height: min(620, screenH * 0.85)))
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Quit: with a running timer or active no sleep (keep-awake) — a branded
    /// confirmation centered on screen instead of silently killing the work.
    private func requestQuit() {
        let busy = model.engine.state == .running
            || model.engine.state == .paused
            || model.keepAwake.isActive
            || model.keepAwake.lidApplied
        guard busy else {
            NSApp.terminate(nil)
            return
        }
        if quitWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            let host = NSHostingController(
                rootView: QuitConfirmView(
                    onQuit: { NSApp.terminate(nil) },
                    onCancel: { [weak self] in self?.quitWindow?.close() }
                )
            )
            host.sizingOptions = []
            window.contentViewController = host
            window.contentMinSize = NSSize(width: 300, height: 140)
            window.contentMaxSize = NSSize(width: 300, height: 400)
            quitWindow = window
        }
        guard let window = quitWindow else { return }
        window.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        if !window.isVisible {
            window.setContentSize(NSSize(width: 300, height: 160))
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private var aboutHeightObserved = false

    /// The about window height follows the active tab's content
    /// (no empty area at the bottom); the window's top edge stays put.
    private func observeAboutHeightOnce() {
        guard !aboutHeightObserved else { return }
        aboutHeightObserved = true
        NotificationCenter.default.addObserver(
            forName: .init("hopAboutContentHeight"), object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, let window = self.aboutWindow, window.isVisible,
                      let h = note.userInfo?["height"] as? CGFloat else { return }
                let screenH = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
                let titlebar = window.frame.height - window.contentLayoutRect.height
                let target = min(h + titlebar, screenH * 0.85)
                guard abs(window.frame.height - target) > 2 else { return }
                var frame = window.frame
                let topY = frame.maxY
                frame.size.height = target
                frame.origin.y = topY - target
                window.setFrame(frame, display: true, animate: false)
            }
        }
    }

    private func showAboutWindow() {
        if aboutWindow == nil {
            // WITHOUT fullSizeContentView: content does not slide under the translucent
            // title bar (icons "floated" through it while scrolling)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // the window drags only by the title bar: background dragging
            // caught clicks on tabs and chips — the window moved when switching
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            let host = NSHostingController(
                rootView: PanelView(initialTab: .about, standaloneAbout: true)
                    .environmentObject(model)
            )
            // sizingOptions=[] and explicit size: .preferredContentSize made the
            // hosting controller fit the window to content via constraints, which broke
            // the about window's AutoLayout (invalid baselines). Scrolling lives in the view itself
            host.sizingOptions = []
            window.contentViewController = host
            // free resize: vertically the content scrolls, horizontally
            // tabs wrap onto new lines and text reflows
            window.contentMinSize = NSSize(width: 480, height: 300)
            window.contentMaxSize = NSSize(width: 100_000, height: 100_000)
            aboutWindow = window
        }
        guard let window = aboutWindow else { return }
        window.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        window.backgroundColor = NSColor(Theme.background) // title bar matches the panel color
        observeAboutHeightOnce()
        if !window.isVisible {
            let screenH = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
            // taller: the "general" tab must fit without scrolling
            window.setContentSize(NSSize(width: 700, height: min(780, screenH * 0.85)))
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func syncSystemTheme() {
        Theme.systemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        applyAppTheme()
    }

    /// Repaint everything at once: popover, windows, menu bar icon.
    func applyAppTheme() {
        statusController?.applyTheme()
        settingsWindow?.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        converterWindow?.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        aboutWindow?.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        quitWindow?.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        model.themeVersion &+= 1 // redraw everything, including views with unchanged inputs
        AppIcon.apply() // the "auto" icon follows the system theme
    }

    /// Window height = content (up to 70% of the screen) until the user
    /// drags an edge themselves — then their choice is respected until close.
    private func adjustConverterHeight() {
        guard let window = converterWindow, window.isVisible,
              !converterUserResized else { return }
        let content = model.converterContentHeight
        guard content > 120 else { return }
        // fullSizeContentView: the scroll view gets a top inset under the title bar —
        // without it the window falls short of the content by that amount and the bottom looks like a "hole"
        let topInset = window.contentView?.safeAreaInsets.top ?? 0
        let screenHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let target = min(content + topInset, screenHeight * 0.75)
        var frame = window.frame
        let currentContent = window.contentRect(forFrameRect: frame).height
        let newHeight = frame.height + (target - currentContent)
        guard abs(newHeight - frame.height) > 2 else { return }
        // center the growth: both down and up — the window doesn't "creep" toward a screen edge
        frame.origin.y += (frame.height - newHeight) / 2
        frame.size.height = newHeight
        converterExpectedHeight = window.contentRect(forFrameRect: frame).height
        window.setFrame(frame, display: true)
    }

    private func showConverterWindow() {
        if converterWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // the window drags only by the title bar: background dragging
            // caught clicks on tabs and chips — the window moved when switching
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            let host = NSHostingController(
                rootView: ConvertWindowView().environmentObject(model)
            )
            // the window resizes only vertically (content sits in a ScrollView);
            // auto-fitting the window size to content is disabled, otherwise
            // the hosting controller would reset the user's height at every hiccup
            host.sizingOptions = []
            window.contentViewController = host
            // width is fixed — only the height stretches
            window.contentMinSize = NSSize(width: 540, height: 200)
            window.contentMaxSize = NSSize(width: 540, height: 100_000)
            converterWindow = window
        }
        guard let window = converterWindow else { return }
        window.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        // CUSTOM presentation without fittingSize: the window has auto-sizing off and
        // maxHeight:.infinity, so fittingSize degenerates to 0 — because of that
        // the window kept opening at 1x1 and was invisible. Set an explicit
        // sensible size, center, show — adjustConverterHeight then
        // fits the height to the content
        if !window.isVisible {
            // fresh open — auto-height to content again; record the initial size
            // as programmatic, otherwise didResize flags it as "user resized"
            // and auto-fit turns off forever (the window got stuck large with a hole)
            converterUserResized = false
            converterExpectedHeight = 380
            window.setContentSize(NSSize(width: 540, height: 380))
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // fit to content — after the PreferenceKey reports the height
        DispatchQueue.main.async { [weak self] in
            self?.adjustConverterHeight()
        }
    }

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 380),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // onboarding is pinned: only windows with a title bar move
        // (about, converter) — clicks on chips don't drag the window
        window.isMovableByWindowBackground = false
        window.isMovable = false
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: OnboardingView(updater: model.updater) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.applyAppTheme() // theme picked in onboarding applies everywhere immediately
        })
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        LaunchGuard.markStable()
    }

    /// Safe mode: only an AppKit menu and the updater, no model,
    /// no SwiftUI — a minimal surface with nothing left to crash.
    private func enterSafeMode() {
        NSLog("HOP-DIAG safe mode entered")
        let lang = L10n.current
        let updater = UpdateChecker()
        safeUpdater = updater

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "exclamationmark.triangle",
            accessibilityDescription: "Hop"
        )

        let menu = NSMenu()
        let title = NSMenuItem(
            title: "Hop — " + L10n.t(.safeModeTitle, lang),
            action: nil, keyEquivalent: ""
        )
        title.isEnabled = false
        menu.addItem(title)
        let hint = NSMenuItem(
            title: L10n.t(.safeModeHint, lang).capitalizedFirst,
            action: nil, keyEquivalent: ""
        )
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.isHidden = true
        menu.addItem(status)

        let check = NSMenuItem(
            title: L10n.t(.checkUpdates, lang).capitalizedFirst,
            action: #selector(safeModeCheckUpdates), keyEquivalent: ""
        )
        check.target = self
        menu.addItem(check)
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: L10n.t(.menuQuit, lang).capitalizedFirst,
            action: #selector(safeModeQuit), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        menu.autoenablesItems = false
        item.menu = menu
        safeStatusItem = item

        // check status shown right in a menu item
        safeStatusSink = updater.$status
            .receive(on: RunLoop.main)
            .sink { [weak status, weak check] state in
                let key: L10nKey?
                switch state {
                case .idle: key = nil
                case .checking: key = .updDownloading
                case .upToDate: key = .upToDate
                case .downloading: key = .updDownloading
                case .installing: key = .updInstalling
                case .failed: key = .updFailed
                }
                status?.isHidden = (key == nil)
                status?.title = key.map { L10n.t($0, L10n.current).capitalizedFirst } ?? ""
                check?.isEnabled = (state != .downloading && state != .installing)
            }

        // try updating right away: the crash is most likely already fixed in a newer version
        Task { @MainActor [weak updater] in
            await updater?.check(manual: true)
        }
    }

    @objc private func safeModeCheckUpdates() {
        Task { @MainActor [weak self] in
            await self?.safeUpdater?.check(manual: true)
        }
    }

    @objc private func safeModeQuit() {
        NSApp.terminate(nil)
    }
}

@main
struct HopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Snapshot.runIfRequested()
    }

    var body: some Scene {
        // the entire UI lives in NSStatusItem + NSPopover (StatusItemController);
        // SwiftUI just formally requires an empty scene
        Settings {
            EmptyView()
        }
    }
}
