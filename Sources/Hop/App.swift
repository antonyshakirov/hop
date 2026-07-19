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
    private var torrentAddWindow: NSWindow?
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

        // Registered defaults. "display stays on" defaults ON: keep-awake should keep
        // the MONITOR awake, not just the system — a caffeine tool that lets the screen
        // sleep by default is a surprise ("I pressed keep-awake and the monitor still
        // turned off"). Registered rather than written, so a user who explicitly turns
        // it off still wins, and BOTH readers agree: the settings toggle (@AppStorage)
        // and the controller (UserDefaults.bool(forKey:)) — which returned false for the
        // never-set key, so the assertion was PreventUserIdleSystemSleep and the display
        // slept regardless of what the toggle appeared to show.
        UserDefaults.standard.register(defaults: [
            KeepAwakeController.keepDisplayKey: true,
        ])

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
            self?.model.activity.note()
            self?.model.engine.toggle()
        }
        hotkeys.setHandler(.awake) { [weak self] in
            guard let awake = self?.model.keepAwake else { return }
            self?.model.activity.note()
            if awake.isActive {
                awake.deactivate()
            } else if let longest = KeepAwakeController.options.last {
                awake.activate(longest)
            }
        }
        // Register the window-snap zone hotkeys ONCE at launch (they were only
        // registered on the first keep-awake keypress — the misplaced call above —
        // so all 18 tiling shortcuts were silently dead on a fresh launch). The
        // call itself is gated on the windows-hotkeys toggle inside.
        hotkeys.refreshSnapHotkeys()

        let model = self.model
        model.updater.startAutoChecks { critical in
            // a set timer (running or paused) is never interrupted; otherwise a
            // release installs only when the user isn't actively using Hop —
            // see UpdateInstallPolicy for the full rule
            let timerBusy = !(model.engine.state == .idle || model.engine.state == .finished)
            return UpdateInstallPolicy.canInstall(
                critical: critical,
                timerBusy: timerBusy,
                keepAwakeActive: model.keepAwake.isActive,
                panelOpen: model.isPanelOpen?() ?? false,
                converterBusy: model.converter.busy,
                secondsSinceInteraction: model.activity.secondsSinceInteraction()
            )
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
        model.openTorrentAddSheet = { [weak self] source in
            self?.showTorrentAddWindow(source)
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
            // back UNDER the frontmost app instead of on top with the panel.
            let ours = Set([converterWindow, settingsWindow, aboutWindow, torrentAddWindow]
                .compactMap { $0 })
            // Raise them WITHOUT reshuffling: walk the current front-to-back
            // order in reverse (back first) so each orderFrontRegardless lands
            // the windows on top in the SAME relative order the user arranged.
            // A fixed array order here reshuffled the user's windows on every
            // panel summon (Anton, 2026-07-19). orderedWindows already excludes
            // miniaturized windows, so a minimized window stays in the Dock.
            for window in NSApp.orderedWindows.reversed()
            where ours.contains(window) && window.isVisible {
                window.orderFrontRegardless()
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

        // Launch finished: the model is built, the crash-loop guard has passed and
        // the add sheet is wired. Only now flush any .torrent/magnet URLs that
        // arrived during a cold launch (see `application(_:open:)`). Not reached in
        // safe mode — that path returns above, so buffered opens stay dropped.
        flushPendingOpens()

        // Repopulate the torrent list from the engine's persisted session, so a
        // relaunch (or a dev reinstall) doesn't leave active torrents invisible in
        // the panel while they keep running in the engine. No-op when nothing was
        // saved or the engine isn't installed. This was never wired — torrents only
        // "survived" a restart when `open` reused the running instance.
        Task {
            // First reap any engine orphaned by a previous instance: a reinstall's
            // SIGKILL bypasses applicationWillTerminate, leaving rqbit holding the
            // DHT/peer ports — which then blocks OUR engine from starting and the
            // panel comes up empty. Explicit here as a backstop to the reap inside
            // start(), so a lingering orphan can never wedge launch.
            if let bin = model.torrent.installer.installedBinaryURL() {
                await TorrentEngineProcess.reapOrphanedEngines(binary: bin)
            }
            await model.torrent.restore()
        }
    }

    private func showSettingsWindow() {
        model.activity.note() // opening a window counts as active use
        if settingsWindow == nil {
            let window = NSWindow(
                // 720 wide so the "modules & tabs" table reads 5 columns
                // (up to 4 spaces + the inactive column) without cramping
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
                // miniaturizable like the converter: settings can be sent to
                // the Dock instead of only closed. WITHOUT fullSizeContentView,
                // like the about window: content must not slide under the
                // translucent title bar (rows showed through it while scrolling)
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // the window drags only by the title bar: background dragging
            // caught clicks on tabs and chips — the window moved when switching
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            let host = NSHostingController(
                rootView: PanelView(initial: .settings, standaloneSettings: true)
                    .environmentObject(model)
            )
            // same reliable path as about/converter: explicit size +
            // sizingOptions=[] so the hosting controller doesn't break AutoLayout with constraints
            host.sizingOptions = []
            window.contentViewController = host
            window.contentMinSize = NSSize(width: 720, height: 300)
            window.contentMaxSize = NSSize(width: 720, height: 100_000)
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
            window.setContentSize(NSSize(width: 720, height: min(620, screenH * 0.85)))
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
        model.activity.note() // opening a window counts as active use
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
                rootView: PanelView(initial: .about, standaloneAbout: true)
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

    /// The torrent add sheet (file selection + destination). A window, like the
    /// converter: the popover collapses on any outside click. Each call rebuilds
    /// the content for the new source; the sheet fetches its own file list.
    private func showTorrentAddWindow(_ source: TorrentController.AddSource) {
        if torrentAddWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
                // no fullSizeContentView: rows must not slide under the
                // translucent title bar (same reason as settings/about).
                // miniaturizable like the converter/settings so the window is a
                // real, minimizable window that survives the popover closing.
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 440, height: 220)
            window.contentMaxSize = NSSize(width: 440, height: 100_000)
            torrentAddWindow = window
        }
        guard let window = torrentAddWindow else { return }
        let host = NSHostingController(
            rootView: TorrentAddSheet(source: source, torrent: model.torrent) { [weak self] in
                self?.torrentAddWindow?.close()
            }
            .environmentObject(model)
        )
        // preferredContentSize: the window tracks the sheet's own fitting height
        // (now that the view dropped its maxHeight:.infinity frame). It opens snug
        // around the "fetching…"/error state and grows when the file list resolves,
        // instead of a fixed height with a hole below. The list scrolls inside its
        // own 300pt cap, so the window height stays bounded; contentMaxSize keeps
        // it on-screen as a backstop.
        host.sizingOptions = [.preferredContentSize]
        window.contentViewController = host
        window.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        let screenH = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        window.contentMaxSize = NSSize(width: 440, height: screenH * 0.85)
        window.center()
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
        torrentAddWindow?.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
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
        model.activity.note() // opening a window counts as active use
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
            // Torrents kept active in onboarding = fetch the engine right away,
            // in the background — the module is ready before its first download.
            if !PanelView.storedModuleIsInactive("torrent") {
                self?.model.torrent.prefetchEngineIfNeeded()
            }
        })
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        LaunchGuard.markStable()
        // Kill the torrent engine on a clean quit: rqbit is a child process that
        // would otherwise be reparented to launchd and keep holding its fixed
        // DHT/peer ports, so the NEXT launch could not start its own engine.
        // Guard on statusController (set only on a normal launch) so we never
        // force-create the lazy model in safe mode. A crash/SIGKILL still orphans
        // the engine — TorrentEngineProcess reaps those on the next start.
        if statusController != nil { model.torrent.stopEngine() }
    }

    // MARK: - Opening .torrent files and magnet: links (Launch Services)

    /// URLs that Launch Services handed us before the app finished launching — the
    /// common case, since a cold double-click of a `.torrent`/magnet delivers
    /// `application(_:open:)` BEFORE `applicationDidFinishLaunching`. They wait here
    /// and are flushed by `flushPendingOpens()` at the end of launch, so the
    /// crash-loop guard and the model build always run first.
    private var pendingOpenURLs: [URL] = []
    /// Flipped true at the very end of `applicationDidFinishLaunching` (never in
    /// safe mode). Until then the open handler must not touch the model or show UI.
    private var appDidFinishLaunching = false

    /// A double-clicked `.torrent` file or a clicked `magnet:` link, delivered here
    /// by Launch Services. On a COLD launch this runs BEFORE
    /// `applicationDidFinishLaunching`: the model does not exist yet and the
    /// crash-loop guard has not run, so such URLs are buffered and flushed once
    /// launch finishes. A warm open (app already up, not in safe mode) is processed
    /// immediately. The handler itself never touches the model, shows an alert, or
    /// builds anything — that would defeat the safe-mode invariant.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if appDidFinishLaunching && safeStatusItem == nil {
                processOpen(url)
            } else {
                pendingOpenURLs.append(url)
            }
        }
    }

    /// Process the URLs that arrived during a cold launch. Called at the very end of
    /// `applicationDidFinishLaunching`, so the model is built, the crash-loop guard
    /// has passed and `openTorrentAddSheet` is wired. Never called in safe mode.
    private func flushPendingOpens() {
        appDidFinishLaunching = true
        let urls = pendingOpenURLs
        pendingOpenURLs = []
        for url in urls { processOpen(url) }
    }

    /// Turn an incoming `.torrent` file or `magnet:` URL into an `AddSource` and
    /// hand it to the add sheet — but only once the engine is installed. With no
    /// engine (the common case until it is hosted) the sheet would sit on
    /// "fetching…" forever, so instead we make the torrent module visible and
    /// point the user at the enable-torrents step. Never hangs, never crashes.
    /// Only ever called past launch and outside safe mode, so touching the model
    /// and showing UI here is safe.
    private func processOpen(_ url: URL) {
        let source: TorrentController.AddSource
        if url.isFileURL {
            guard url.pathExtension.lowercased() == "torrent" else { return }
            guard let data = try? Data(contentsOf: url) else {
                // moved / deleted / no permission: tell the user instead of a
                // silent return. Safe to alert here — we are always past launch.
                let lang = L10n.current
                let alert = NSAlert()
                alert.messageText = L10n.t(.torrentReadFailed, lang).capitalizedFirst
                alert.alertStyle = .warning
                alert.runModal()
                return
            }
            source = .file(data)
        } else if url.scheme?.lowercased() == "magnet" {
            source = .link(url.absoluteString)
        } else {
            return
        }

        // make the torrent module visible so its CTA sits where the user
        // expects: lift it out of the inactive bucket onto the first space
        PanelView.activateStoredModule("torrent")
        NSApp.activate(ignoringOtherApps: true)

        guard model.torrent.installer.installedBinaryURL() != nil else {
            let lang = L10n.current
            let alert = NSAlert()
            alert.messageText = L10n.t(.torrentLabel, lang).capitalizedFirst
            alert.informativeText = L10n.t(.torrentEnable, lang).capitalizedFirst
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        model.openTorrentAddSheet?(source)
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

/// Headless self-test for the torrent hub, mirroring `Snapshot.runIfRequested()`:
/// `Hop --torrent-selftest <binaryPath> <source>` spins up a real engine against
/// a local rqbit binary, adds a torrent, polls progress, and exits — the menu bar
/// app is never launched.
@MainActor
enum TorrentSelfTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--torrent-selftest"), args.count > i + 2 else { return }
        let binaryPath = args[i + 1]
        let rawSource = args[i + 2]

        // A magnet or http(s) URL is a link; anything else that names an existing
        // file is a `.torrent` read as raw bytes — this exercises the byte path.
        let source: TorrentController.AddSource
        let lower = rawSource.lowercased()
        if lower.hasPrefix("magnet:") || lower.hasPrefix("http") {
            source = .link(rawSource)
        } else if let data = try? Data(contentsOf: URL(fileURLWithPath: rawSource)) {
            source = .file(data)
        } else {
            print("SELFTEST FAIL: source is neither a magnet/http link nor a readable file: \(rawSource)")
            exit(1)
        }

        // Run the async flow on the main actor and exit when it completes. The
        // run loop below keeps the process alive so continuations can progress —
        // same "pump the main run loop" approach the snapshot path already uses
        // (RunLoop.main.run(until:)), no MainActor-blocking semaphore.
        Task { @MainActor in
            let controller = TorrentController()
            do {
                let pending = try await controller.fetchFiles(
                    source: source, binaryOverride: URL(fileURLWithPath: binaryPath))
                print("files=\(pending.files.count) name=\(pending.name)")
                try await controller.confirmAdd(pending, selectedIndices: Set(pending.files.map { $0.index }))
                for _ in 0..<10 {
                    await controller.pollOnce()
                    if let s = controller.torrents.first?.stats {
                        let pct = String(format: "%.2f", s.fraction * 100)
                        print("progress=\(pct)% down=\(s.downloadBps)B/s up=\(s.uploadBps)B/s "
                            + "peers=\(s.peersLive)/\(s.peersSeen) finished=\(s.finished ? "yes" : "no")")
                    }
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                }
                controller.stopEngine()
                print("SELFTEST OK")
                exit(0)
            } catch {
                controller.stopEngine()
                print("SELFTEST FAIL: \(error)")
                exit(1)
            }
        }
        RunLoop.main.run()
    }
}

@main
struct HopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Dev-only entry points, gated out of release:
        //  • --torrent-selftest runs an ARBITRARY binary path (skipping the engine
        //    signature check) — a launch-arbitrary-binary gadget if shipped.
        //  • --snapshot / --menubar-icons write PNGs to arbitrary caller-supplied
        //    paths, and --demo overwrites the user's real clipboard history.
        // None of these are reachable in the shipped, notarized Hop.
        #if DEBUG
        TorrentSelfTest.runIfRequested()
        Snapshot.runIfRequested()
        #endif
    }

    var body: some Scene {
        // the entire UI lives in NSStatusItem + NSPopover (StatusItemController);
        // SwiftUI just formally requires an empty scene
        Settings {
            EmptyView()
        }
    }
}
