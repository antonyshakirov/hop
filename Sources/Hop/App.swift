import AppKit
import Combine
import SwiftUI
import HopCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // lazy: model initialization must not run before the crash-loop check —
    // in safe mode the model (and everything that could crash) is never created at all
    lazy var model = AppModel()
    private let reminders = ReminderScheduler()
    /// Command and state files an outside agent reads and writes.
    private var agent: AgentBridge?
    /// Picks up to-do edits made outside the app, so a task an agent appends to
    /// todos.json shows up instead of being overwritten by the next save.
    private var todosWatcher: FileWatcher?
    /// Drives reminder firing independently of the notification centre, so a
    /// reminder still lands with banners switched off. 15s with a wide tolerance:
    /// the comparison is two dates, and the banner itself is second-accurate.
    private var reminderTicker: Timer?
    private var safeStatusItem: NSStatusItem?
    private var safeUpdater: UpdateChecker?
    private var safeStatusSink: AnyCancellable?
    private var statusController: StatusItemController?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var converterWindow: ConverterWindow?
    private var archiveWindow: ConverterWindow?
    private var uninstallWindow: NSWindow?
    private var uninstallUserResized = false
    private var uninstallExpectedHeight: CGFloat = 0
    private var uninstallHeightSink: AnyCancellable?
    private var finderArchiveWindows: [UUID: FinderArchiveProgressWindowController] = [:]
    private var screenTextWindow: ConverterWindow?
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
    private var archiveHeightSink: AnyCancellable?
    private var archiveUserResized = false
    private var archiveExpectedHeight: CGFloat = -1
    private var screenTextHeightSink: AnyCancellable?
    private var screenTextUserResized = false
    private var screenTextExpectedHeight: CGFloat = -1
    private var converterPasteMonitor: Any?
    private var dockWindowSink: Any?

    // MARK: - Dock presence

    /// The windows that earn Hop a Dock icon while they are open. The panel is
    /// deliberately absent: it hangs off the status item and closes on any
    /// outside click, so it is part of the menu bar rather than a window
    /// someone would look for in the Dock. The quit confirmation is absent for
    /// the same reason — it lives for a second and answers one question.
    private var dockWindows: [NSWindow] {
        var list = [settingsWindow, aboutWindow, torrentAddWindow, converterWindow,
                    archiveWindow, uninstallWindow, screenTextWindow,
                    onboardingWindow].compactMap { $0 }
        list.append(contentsOf: finderArchiveWindows.values.map(\.window))
        return list
    }

    private var wantsDockIcon: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.showWindowsInDock) as? Bool ?? true
    }

    /// Hop is a menu-bar app with no Dock icon, which is right until it opens a
    /// window of its own. A window that cannot be reached from the Dock has to
    /// be found through the panel every time, and the panel is the whole app
    /// when all the user wanted was the converter (Anton, 2026-07-28).
    ///
    /// Called BEFORE the window is ordered in: switching policy after it is on
    /// screen makes the app blink out of focus and the window drop behind
    /// whatever was in front.
    private func enterDockMode() {
        guard !Snapshot.active, wantsDockIcon,
              NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
    }

    /// Back to a plain menu-bar app once the last of those windows has gone —
    /// an icon in the Dock for an app with nothing open is the thing people
    /// pick a menu-bar utility to avoid.
    private func leaveDockModeIfIdle() {
        guard !Snapshot.active, NSApp.activationPolicy() != .accessory,
              !dockWindows.contains(where: \.isVisible) else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// A click on the Dock icon must land on the window the icon is there for,
    /// including when that window is only minimized.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        guard let window = dockWindows.first(where: \.isMiniaturized)
                ?? dockWindows.first(where: \.isVisible)
                ?? dockWindows.first else { return false }
        window.deminiaturize(nil)
        enterDockMode()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return false
    }

    /// Reminders: reconcile at launch, on every tick and on wake, and keep the
    /// system's pending requests in step with the list. A snapshot render skips
    /// the lot — it never loaded the real list in the first place.
    private func startReminders() {
        guard !Snapshot.active else { return }
        let todos = model.todos
        todos.onRemindersChanged = { [weak self] list in self?.reminders.reschedule(list) }
        reminders.install(todos: todos)
        todos.reconcile()

        // A safety net only: the precise per-reminder timer in TodosController is
        // what makes a reminder land on time. This catches a machine that slept
        // through one, or a clock that jumped.
        let ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in todos.reconcile() }
        }
        ticker.tolerance = 10
        reminderTicker = ticker

        // Sleeping through a firing is the normal case for a laptop: the ticker
        // does not run while asleep, so catch up the moment the Mac is back.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in todos.reconcile() }
        }
    }

    /// The file surface an agent talks to, plus the watcher that makes a hand
    /// edit of todos.json visible while the app is running.
    private func startAgentBridge() {
        guard !Snapshot.active else { return }
        let todos = model.todos
        let bridge = AgentBridge(directory: todos.storeDirectory)
        bridge.onOpenPanel = { [weak self] in self?.statusController?.togglePanel() }
        bridge.start(model: model)
        agent = bridge

        let watcher = FileWatcher(url: todos.storeDirectory.appendingPathComponent("todos.json")) {
            Task { @MainActor in todos.reloadFromDisk() }
        }
        watcher.start()
        todosWatcher = watcher
    }

    /// The Dock icon leaves with the last window. `willClose` arrives while the
    /// window still reports itself visible, so the check waits one turn of the
    /// run loop — otherwise the app would keep its icon until the next window.
    private func observeDockWindowClosing() {
        dockWindowSink = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let closing = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard let self, self.dockWindows.contains(where: { $0 === closing }) else { return }
                DispatchQueue.main.async { [weak self] in self?.leaveDockModeIfIdle() }
            }
        }
    }

    /// Throws away what the URL cache left before Hop switched it off. Runs once
    /// per machine, on the first launch of a build that carries this: the files
    /// are ours, in our own cache folder, so nothing is asked of the user and
    /// nothing of theirs is touched — only `Cache.db` and the fetched-file folder
    /// the URL loading system writes. Deleting them is what "we keep no cache"
    /// means for someone updating rather than installing fresh (Anton,
    /// 2026-07-30).
    private static func dropOwnHTTPCache() {
        let done = "httpCacheDropped"
        guard !UserDefaults.standard.bool(forKey: done) else { return }
        UserDefaults.standard.set(true, forKey: done)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let ours = caches?.appendingPathComponent(Bundle.storageIdentifier) else { return }
        for name in ["Cache.db", "Cache.db-shm", "Cache.db-wal", "fsCachedData"] {
            try? FileManager.default.removeItem(at: ours.appendingPathComponent(name))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent without a Dock icon — including dev runs via `swift run`.
        NSApp.setActivationPolicy(.accessory)

        // Hop keeps no HTTP cache on disk. It never asked for one: macOS gives
        // every app a URL cache, and Hop's few downloads — the update check, the
        // speed test, the 7-Zip helper — filled ~/Library/Caches/…/Cache.db with
        // megabytes of write-ahead log that nothing here ever reads again (Anton
        // found Hop in its own cache list, 2026-07-30). Zero on both ends: a
        // one-shot download has nothing to gain from being cached, and a speed
        // test served from a cache would measure the wrong thing.
        // Tooltips after a second: the system's lazy couple of seconds arrives
        // after the pointer has moved on, and a third of a second fires while
        // the pointer is only passing through, which reads as twitchy (Anton
        // tried both, 2026-07-30).
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 1000])

        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        Self.dropOwnHTTPCache()

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
        // The reminder signal ships fully on: a reminder nobody hears is not a
        // reminder. Registered rather than written, so an explicit OFF wins.
        UserDefaults.standard.register(defaults: SettingsKey.registeredDefaults)

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

        observeDockWindowClosing()

        statusController = StatusItemController(model: model)
        startReminders()
        startAgentBridge()

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
        hotkeys.setHandler(.color) { [weak self] in
            self?.model.activity.note()
            self?.model.colorPicker.pick()
        }
        hotkeys.setHandler(.ocr) { [weak self] in
            self?.model.activity.note()
            self?.model.screenText.capture()
        }
        hotkeys.setHandler(.keyboardLock) { [weak self] in
            self?.model.activity.note()
            self?.model.keyboardLock.lock()
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
        model.openArchiveWindow = { [weak self] in
            self?.showArchiveWindow()
        }
        model.openUninstallWindow = { [weak self] in
            self?.showUninstallWindow()
        }
        model.openScreenTextWindow = { [weak self] in
            self?.showScreenTextWindow()
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
            let ours = Set([converterWindow, settingsWindow, aboutWindow, torrentAddWindow,
                            archiveWindow, uninstallWindow,
                            screenTextWindow].compactMap { $0 }
                + finderArchiveWindows.values.map(\.presentedWindow))
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
        // the archive window follows the same rule: empty module = drop plate only
        archiveHeightSink = model.$archiveContentHeight
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.adjustArchiveHeight() }
        // and so does the recognition window: plate only until there is a result
        screenTextHeightSink = model.$screenTextContentHeight
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.adjustScreenTextHeight() }
        // and the uninstaller: plate only until an app is dropped, then a list
        uninstallHeightSink = model.$uninstallContentHeight
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.adjustUninstallHeight() }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, let resized = note.object as? NSWindow else { return }
                if resized === self.converterWindow {
                    let height = resized.contentRect(forFrameRect: resized.frame).height
                    if abs(height - self.converterExpectedHeight) > 1 {
                        self.converterUserResized = true
                    }
                } else if resized === self.archiveWindow {
                    let height = resized.contentRect(forFrameRect: resized.frame).height
                    if abs(height - self.archiveExpectedHeight) > 1 {
                        self.archiveUserResized = true
                    }
                } else if resized === self.uninstallWindow {
                    let height = resized.contentRect(forFrameRect: resized.frame).height
                    if abs(height - self.uninstallExpectedHeight) > 1 {
                        self.uninstallUserResized = true
                    }
                } else if resized === self.screenTextWindow {
                    let height = resized.contentRect(forFrameRect: resized.frame).height
                    if abs(height - self.screenTextExpectedHeight) > 1 {
                        self.screenTextUserResized = true
                    }
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, let closing = note.object as? NSWindow else { return }
                // next open — auto-fit again
                if closing === self.converterWindow { self.converterUserResized = false }
                if closing === self.archiveWindow { self.archiveUserResized = false }
                if closing === self.uninstallWindow { self.uninstallUserResized = false }
                if closing === self.screenTextWindow { self.screenTextUserResized = false }
            }
        }

        // Diagnostics: open a window straight from a launch flag (no UI click) and
        // log its frame to the system log. Dev/snapshot builds only — the
        // Bundle.isDevBuild gate (the same one the updater and dev-badge share)
        // keeps both the flags and the HOP-DIAG logging out of the shipped
        // release app, which is compiled -c release like the dev app, so #if DEBUG
        // would not tell them apart.
        if Bundle.isDevBuild {
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
                    .hopLayoutDirection()
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
        enterDockMode()
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
                .hopLayoutDirection()
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
    // First open: the about window is ordered in TRANSPARENT and revealed only
    // once the first content-height report arrives, so it is never seen at a
    // guessed height (house invariant: laid out before it is shown). Later opens
    // reuse the retained, already-correct frame — the active tab is remembered.
    private var aboutAwaitingReveal = false
    private var aboutHasBeenSized = false

    /// The about window height follows the active tab's content
    /// (no empty area at the bottom); the window's top edge stays put.
    private func observeAboutHeightOnce() {
        guard !aboutHeightObserved else { return }
        aboutHeightObserved = true
        NotificationCenter.default.addObserver(
            forName: .init("hopAboutContentHeight"), object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, let window = self.aboutWindow,
                      let h = note.userInfo?["height"] as? CGFloat else { return }
                let screenH = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
                let titlebar = window.frame.height - window.contentLayoutRect.height
                // integral height only — a fractional window height made the
                // hosting controller re-measure and jump the content on open.
                //
                // The ceiling is the usable screen minus a small margin, NOT a
                // fraction of it. At 0.85 a 855pt work area capped the window at
                // 727pt while the "general" tab needs ~810 (780 of content plus
                // the title bar) — so the window opened cut off exactly below the
                // description and the support card at the foot of it was never
                // seen (Anton, 2026-07-28). visibleFrame already excludes the menu
                // bar and the Dock, so its height IS the limit; the 12pt keeps the
                // window off the very edges.
                let ceiling = (screenH - 12).rounded(.down)
                let target = min((h + titlebar).rounded(.up), ceiling)

                if self.aboutAwaitingReveal {
                    // the first frame after ordering in transparent: size to the
                    // content, recenter at that final height, then reveal — so the
                    // very first appearance is already correct, no visible resize
                    self.aboutAwaitingReveal = false
                    self.aboutHasBeenSized = true
                    var frame = window.frame
                    frame.size.height = target
                    window.setFrame(frame, display: false, animate: false)
                    window.center()
                    window.alphaValue = 1
                    return
                }
                guard window.isVisible else { return }
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
                // 1060 wide so all ELEVEN section tabs sit on ONE line in the
                // widest language (the "tasks & time" tab was added 2026-07-21 for
                // the tracker + to-do modules; ~130pt of natural-width chip on top
                // of the previous ten's ~919pt, rounded up for margin).
                // Still freely resizable — narrower widths wrap the tabs (FlowLayout).
                contentRect: NSRect(x: 0, y: 0, width: 1060, height: 560),
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
                    .hopLayoutDirection()
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
            if aboutHasBeenSized {
                // reopen: the retained frame is already sized to the last-shown
                // tab (the section is remembered) — just recenter and show.
                window.center()
            } else {
                // first open ever: the content height is unknown until SwiftUI
                // lays out, so order in transparent at the target WIDTH (1060 —
                // all section tabs on one line, matching the window's own width;
                // 940 was stale, from when there were ten tabs) and let the first
                // height report size, recenter and reveal it.
                aboutAwaitingReveal = true
                window.alphaValue = 0
                window.setContentSize(NSSize(width: 1060, height: min(820, screenH - 12)))
                window.center()
            }
        }
        enterDockMode()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if aboutAwaitingReveal {
            // safety net: if the height report never arrives (it should, on the
            // first appear), reveal at the provisional size rather than leave an
            // invisible window — no worse than the old fixed-height behavior.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.aboutAwaitingReveal, let window = self.aboutWindow else { return }
                self.aboutAwaitingReveal = false
                self.aboutHasBeenSized = true
                window.alphaValue = 1
            }
        }
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
            .hopLayoutDirection()
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
        enterDockMode()
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
        archiveWindow?.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        finderArchiveWindows.values.forEach { $0.applyTheme() }
        screenTextWindow?.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
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
            let window = ConverterWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            // Hop is an accessory app with no Edit menu, so ⌘V has no Paste
            // key-equivalent to drive SwiftUI's onPasteCommand. The window
            // catches ⌘V itself (performKeyEquivalent), so paste works whenever
            // the window is key regardless of which subview holds focus.
            window.onPaste = { [weak self] in self?.model.converter.addFromPasteboard() }
            // performKeyEquivalent is only offered to NSApp.keyWindow. Opening
            // the converter from a background state (the user copied in Finder,
            // then triggered Hop) activates the app asynchronously — on macOS
            // 14+ cooperative activation it can lag or be denied — so keyWindow
            // is nil when ⌘V is pressed and the key-equivalent reaches no window,
            // silently dropping the paste. A local keyDown monitor fires before
            // that routing, so paste no longer depends on the window being key.
            converterPasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
                // Match the PHYSICAL V key (keyCode 9), not the produced character:
                // a non-Latin layout maps ⌘V to a different character (a Cyrillic
                // letter on a Russian layout, not "v"), so a character check
                // silently dropped the paste. ⌘V and ⌘⇧V both count.
                guard let self, let window,
                      KeyChord.isPasteChord(
                        keyCode: event.keyCode,
                        modifierFlags: event.modifierFlags.rawValue),
                      // another Hop window can be key and want ⌘V for itself
                      // (the recognition window pastes a picture, the archive
                      // window queues the copied files)
                      self.screenTextWindow?.isKeyWindow != true,
                      self.archiveWindow?.isKeyWindow != true,
                      ConverterPaste.shouldIngest(
                        windowVisible: window.isVisible,
                        windowIsKey: window.isKeyWindow,
                        hasKeyWindow: NSApp.keyWindow != nil)
                else { return event }
                self.model.converter.addFromPasteboard()
                return nil // consumed — never double-fires with performKeyEquivalent
            }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // the window drags only by the title bar: background dragging
            // caught clicks on tabs and chips — the window moved when switching
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            let host = NSHostingController(
                rootView: ConvertWindowView().environmentObject(model)
                    .hopLayoutDirection()
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
        enterDockMode()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // fit to content — after the PreferenceKey reports the height
        DispatchQueue.main.async { [weak self] in
            self?.adjustConverterHeight()
        }
    }

    /// Height of the archive window from its content, exactly like the
    /// converter's: an empty module is a drop plate and nothing else, and the
    /// window grows only once there are jobs under it (Anton, 2026-07-25).
    private func adjustArchiveHeight() {
        guard let window = archiveWindow, window.isVisible,
              !archiveUserResized else { return }
        let content = model.archiveContentHeight
        guard content > 120 else { return }
        // fullSizeContentView puts the content under the title bar, so the inset
        // has to be added or the window falls short by exactly that much
        let topInset = window.contentView?.safeAreaInsets.top ?? 0
        let screenHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let target = min(content + topInset, screenHeight * 0.75)
        var frame = window.frame
        let currentContent = window.contentRect(forFrameRect: frame).height
        let newHeight = frame.height + (target - currentContent)
        guard abs(newHeight - frame.height) > 2 else { return }
        frame.origin.y += (frame.height - newHeight) / 2   // grow around the centre
        frame.size.height = newHeight
        archiveExpectedHeight = window.contentRect(forFrameRect: frame).height
        window.setFrame(frame, display: true)
    }

    /// The archive window: a drop target that stays put while a file is being
    /// dragged onto it — the panel's popover closes the moment a drag starts, so
    /// the module's row only opens this (Anton, 2026-07-25).
    private func showArchiveWindow() {
        model.activity.note()
        if archiveWindow == nil {
            // ConverterWindow only for its ⌘V handling: Hop has no Edit menu, so
            // paste needs a window that catches the key equivalent itself.
            let window = ConverterWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 260),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.onPaste = { [weak self] in self?.model.archive.addFromPasteboard() }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            let host = NSHostingController(
                rootView: ArchiveWindowView().environmentObject(model)
                    .hopLayoutDirection()
            )
            host.sizingOptions = []
            window.contentViewController = host
            // as short as the drop plate plus the format row: the auto-fit takes
            // it from here, and a taller floor would reintroduce the empty gap
            window.contentMinSize = NSSize(width: 420, height: 200)
            archiveWindow = window
        }
        guard let window = archiveWindow else { return }
        window.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        if !window.isVisible {
            window.setContentSize(NSSize(width: 480, height: 260))
            window.center()
        }
        enterDockMode()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        adjustArchiveHeight()
    }

    /// The uninstaller window: an app goes in (dropped or picked), everything it
    /// left behind comes out as a list with sizes, and what the user ticks moves
    /// to the trash. A plain window — no paste handling, since an app is not
    /// something anybody copies to the clipboard.
    private func showUninstallWindow() {
        model.activity.note()
        if uninstallWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            let host = NSHostingController(
                rootView: UninstallWindowView(uninstall: model.uninstall,
                                              lang: L10n.current)
                    .environmentObject(model)
                    .hopLayoutDirection()
            )
            host.sizingOptions = []
            window.contentViewController = host
            // as short as the drop plate: the fit takes it from here
            window.contentMinSize = NSSize(width: 460, height: 180)
            uninstallWindow = window
        }
        guard let window = uninstallWindow else { return }
        window.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        if !window.isVisible {
            // The clean-up job opens TALL: it is five lists, and a short window put
            // its buttons below the fold, where a button might as well not exist
            // (Anton, 2026-07-30). Removing an app opens at the drop plate's own
            // height and grows from there.
            // Both jobs open TALL: one is five lists, the other is every app on
            // the Mac, and a short window put their content below the fold where
            // a button might as well not exist (Anton, 2026-07-30).
            let clean = model.uninstall.mode == .clean
            let screen = (NSScreen.main?.visibleFrame.height ?? 900)
            window.setContentSize(NSSize(width: clean ? 620 : 560,
                                         height: min(clean ? 760 : 700, screen * 0.8)))
            window.center()
        }
        enterDockMode()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        adjustUninstallHeight()
    }

    /// The uninstaller window follows its content: with only the drop plate on
    /// screen a fixed height leaves a dark void under it. Same shape as the
    /// archive window's fit, including "stop once the user has resized it".
    private func adjustUninstallHeight() {
        guard let window = uninstallWindow, window.isVisible,
              !uninstallUserResized,
              model.uninstall.mode != .clean,
              // the picker scrolls as one screen; fitting the window to a list of
              // every installed app would make it as tall as the display
              model.uninstall.target != nil else { return }
        let content = model.uninstallContentHeight
        guard content > 80 else { return }
        let topInset = window.contentView?.safeAreaInsets.top ?? 0
        let screenHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let target = min(content + topInset, screenHeight * 0.8)
        var frame = window.frame
        let currentContent = window.contentRect(forFrameRect: frame).height
        let newHeight = frame.height + (target - currentContent)
        guard abs(newHeight - frame.height) > 2 else { return }
        frame.origin.y += (frame.height - newHeight) / 2   // grow around the centre
        frame.size.height = newHeight
        uninstallExpectedHeight = window.contentRect(forFrameRect: frame).height
        window.setFrame(frame, display: true)
    }

    /// The recognition window: a picture goes in (dropped or pasted), the text
    /// comes out where it can be read and copied. It reuses ConverterWindow only
    /// for its ⌘V handling — Hop has no Edit menu, so paste needs a window that
    /// catches the key equivalent itself.
    private func showScreenTextWindow() {
        model.activity.note()
        if screenTextWindow == nil {
            let window = ConverterWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.onPaste = { [weak self] in self?.model.screenText.recognizeFromPasteboard() }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            let host = NSHostingController(
                rootView: ScreenTextWindowView().environmentObject(model)
                    .hopLayoutDirection()
            )
            host.sizingOptions = []
            window.contentViewController = host
            // the plate alone is shorter than the old floor, and a floor above
            // the content is exactly what left the gap
            window.contentMinSize = NSSize(width: 520, height: 200)
            screenTextWindow = window
        }
        guard let window = screenTextWindow else { return }
        window.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        // The window is as tall as what it shows: just the drop plate until a
        // result exists, then room for the text as well (Anton, 2026-07-25).
        // A fixed pair of heights left a gap under the plate, so the real
        // content height decides — adjustScreenTextHeight takes it from here.
        if !window.isVisible {
            window.setContentSize(NSSize(width: 560, height: 240))
            window.center()
        }
        enterDockMode()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        adjustScreenTextHeight()
    }

    /// Height of the recognition window from its content, like the converter's
    /// and the archive window's.
    private func adjustScreenTextHeight() {
        guard let window = screenTextWindow, window.isVisible,
              !screenTextUserResized else { return }
        let content = model.screenTextContentHeight
        guard content > 120 else { return }
        let topInset = window.contentView?.safeAreaInsets.top ?? 0
        let screenHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let target = min(content + topInset, screenHeight * 0.75)
        var frame = window.frame
        let currentContent = window.contentRect(forFrameRect: frame).height
        let newHeight = frame.height + (target - currentContent)
        guard abs(newHeight - frame.height) > 2 else { return }
        frame.origin.y += (frame.height - newHeight) / 2   // grow around the centre
        frame.size.height = newHeight
        screenTextExpectedHeight = window.contentRect(forFrameRect: frame).height
        window.setFrame(frame, display: true)
    }

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
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
        window.contentViewController = NSHostingController(rootView: OnboardingView(updater: model.updater, shelves: model.appShelves) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.applyAppTheme() // theme picked in onboarding applies everywhere immediately
            // Torrents kept active in onboarding = fetch the engine right away,
            // in the background — the module is ready before its first download.
            if !PanelView.storedModuleIsInactive("torrent") {
                self?.model.torrent.prefetchEngineIfNeeded()
            }
        }.hopLayoutDirection())
        window.center()
        onboardingWindow = window
        enterDockMode()
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

    // MARK: - Opening archives, .torrent files and magnet: links (Launch Services)

    /// URL batches that Launch Services handed us before the app finished launching
    /// — the common case, since a cold double-click of an archive, `.torrent`, or
    /// magnet delivers
    /// `application(_:open:)` BEFORE `applicationDidFinishLaunching`. They wait here
    /// and are flushed by `flushPendingOpens()` at the end of launch, so the
    /// crash-loop guard and the model build always run first.
    private var pendingOpenBatches: [[URL]] = []
    /// Flipped true at the very end of `applicationDidFinishLaunching` (never in
    /// safe mode). Until then the open handler must not touch the model or show UI.
    private var appDidFinishLaunching = false

    /// Finder-opened archives, a double-clicked `.torrent` file, or a clicked
    /// `magnet:` link, delivered here by Launch Services. On a COLD launch this
    /// runs BEFORE
    /// `applicationDidFinishLaunching`: the model does not exist yet and the
    /// crash-loop guard has not run, so such URLs are buffered and flushed once
    /// launch finishes. A warm open (app already up, not in safe mode) is processed
    /// immediately. The handler itself never touches the model, shows an alert, or
    /// builds anything — that would defeat the safe-mode invariant.
    func application(_ application: NSApplication, open urls: [URL]) {
        if appDidFinishLaunching && safeStatusItem == nil {
            processOpenBatch(urls)
        } else {
            pendingOpenBatches.append(urls)
        }
    }

    /// Process the URLs that arrived during a cold launch. Called at the very end of
    /// `applicationDidFinishLaunching`, so the model is built, the crash-loop
    /// guard has passed and the window callbacks are wired. Never called in safe
    /// mode.
    private func flushPendingOpens() {
        appDidFinishLaunching = true
        let batches = pendingOpenBatches
        pendingOpenBatches = []
        processOpenBatch(batches.flatMap { $0 })
    }

    /// One Finder event can contain several selected archives. They share one
    /// compact progress window, while non-archive URLs keep their existing
    /// torrent/magnet route.
    private func processOpenBatch(_ urls: [URL]) {
        // hop:// links come from Shortcuts, scripts, or anything that can run
        // `open`. Same command vocabulary as the command file, one parser for both.
        let hopLinks = urls.filter { $0.scheme?.lowercased() == "hop" }
        for link in hopLinks {
            guard let command = AgentCommandParser.parse(url: link) else { continue }
            agent?.perform(command)
        }

        let archives = urls.filter {
            $0.isFileURL
                && ((try? $0.resourceValues(
                    forKeys: [.isRegularFileKey]))?.isRegularFile ?? false)
                && ArchiveRules.format(ofFileNamed: $0.lastPathComponent) != nil
        }
        if !archives.isEmpty {
            showFinderArchiveProgress(for: archives)
        }
        for url in urls where !archives.contains(url) && !hopLinks.contains(url) {
            processOpen(url)
        }
    }

    private func showFinderArchiveProgress(for archives: [URL]) {
        let files = archives.map {
            (id: UUID(), fileName: $0.lastPathComponent)
        }
        let controller = FinderArchiveProgressWindowController(
            files: files
        ) { [weak self] id in
            self?.finderArchiveWindows[id] = nil
        }
        finderArchiveWindows[controller.id] = controller
        controller.show()

        for (archive, file) in zip(archives, files) {
            model.archive.openFromFinder(archive) { [weak controller] event in
                controller?.receive(event, for: file.id)
            }
        }
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
        // expects: lift it out of the inactive bucket onto the first space.
        // `placeModule` is the in-panel choke point that pairs activation with
        // `prefetchEngineIfNeeded`; this out-of-panel path is not routed through
        // it, so it must honour the same rule — NO activation path may skip the
        // prefetch — and fetch the engine here too, only when we actually just
        // lifted it out of inactive (matching `placeModule`'s `wasInactive`).
        let torrentWasInactive = PanelView.storedModuleIsInactive("torrent")
        PanelView.activateStoredModule("torrent")
        if torrentWasInactive { model.torrent.prefetchEngineIfNeeded() }
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
        // Dev/snapshot builds only — no HOP-DIAG in the shipped release app.
        if Bundle.isDevBuild { NSLog("HOP-DIAG safe mode entered") }
        let lang = L10n.current
        let updater = UpdateChecker()
        safeUpdater = updater

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "exclamationmark.triangle",
            accessibilityDescription: "Hop"
        )

        let menu = NSMenu()
        menu.applyHopLayoutDirection()
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

/// The standalone converter window handles ⌘V itself. Hop is an accessory
/// (menu-bar) app whose only scene is an empty `Settings` scene, so there is
/// no Edit → Paste menu item and thus no ⌘V key-equivalent to trigger the
/// `paste:` action SwiftUI's `onPasteCommand` listens for — pressing ⌘V would
/// otherwise just beep. Catching it at the window level makes paste reliable
/// whenever the window is key, no matter which subview (if any) has focus.
final class ConverterWindow: NSWindow {
    var onPaste: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Give the responder chain first refusal (a focused text field, a future
        // editable subview): only fall back to the window-level paste when nothing
        // else claimed ⌘V. With no such field today, super returns false and the
        // behavior is unchanged — but this can never silently steal paste later.
        if super.performKeyEquivalent(with: event) { return true }
        // Match the PHYSICAL V key (keyCode 9), not the produced character: a
        // non-Latin layout maps ⌘V to a different character (Cyrillic on a
        // Russian layout, not "v"), which a character check would miss. ⌘V and
        // ⌘⇧V both paste.
        if KeyChord.isPasteChord(keyCode: event.keyCode, modifierFlags: event.modifierFlags.rawValue) {
            onPaste?()
            return true
        }
        return false
    }
}

/// Headless document-conversion check, in the spirit of the torrent self-test:
/// `Hop --doc-selftest <source> <pdf|md|docx> <outDir>` converts one file and
/// prints where it landed. Debug builds only, like every other dev entry point.
@MainActor
enum DocumentSelfTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--doc-selftest"), args.count > i + 3 else { return }
        let source = URL(fileURLWithPath: args[i + 1])
        guard let target = DocumentConversion.Target(rawValue: args[i + 2] == "md"
            ? "markdown" : args[i + 2]) else {
            print("SELFTEST FAIL: unknown target \(args[i + 2])")
            exit(1)
        }
        let outDir = URL(fileURLWithPath: args[i + 3])
        let name = source.deletingPathExtension().lastPathComponent
        let outURL = outDir.appendingPathComponent("\(name).\(target.fileExtension)")

        let ok: Bool
        switch target {
        case .markdown:
            let text = source.pathExtension.lowercased() == "pdf"
                ? DocumentConversion.markdown(fromPDF: source)
                : DocumentConversion.read(source).map { DocumentConversion.markdown(from: $0) }
            ok = text.flatMap { try? $0.write(to: outURL, atomically: true, encoding: .utf8) } != nil
        case .pdf:
            ok = DocumentConversion.read(source).map {
                DocumentConversion.writePDF($0, to: outURL)
            } ?? false
        case .docx:
            let attributed = source.pathExtension.lowercased() == "pdf"
                ? DocumentConversion.markdown(fromPDF: source)
                    .map { DocumentConversion.attributed(markdown: $0) }
                : DocumentConversion.read(source)
            ok = attributed.map { DocumentConversion.writeDocx($0, to: outURL) } ?? false
        }
        print(ok ? "SELFTEST OK: \(outURL.path)" : "SELFTEST FAIL")
        exit(ok ? 0 : 1)
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
        DocumentSelfTest.runIfRequested()
        VideoSelfTest.runIfRequested()
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

/// Headless video-reframing check, the same idea as the document one:
/// `Hop --video-selftest <source> <shape> <fit> <outDir>` converts one file
/// through the real pipeline and prints where it landed, so the shapes and the
/// three fits can be looked at without dragging files into a window.
/// Debug builds only.
@MainActor
enum VideoSelfTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--video-selftest"), args.count > i + 4 else { return }
        let source = URL(fileURLWithPath: args[i + 1])
        guard let shape = VideoFrame.Shape(rawValue: args[i + 2]),
              let fit = VideoFrame.Fit(rawValue: args[i + 3]) else {
            print("SELFTEST FAIL: unknown shape/fit")
            exit(1)
        }
        let outDir = URL(fileURLWithPath: args[i + 4])
        // optional 5th argument: the squeeze dial, 0…100, or "off" for no
        // compression at all — the settings themselves are not touched
        let dial = args.count > i + 5 ? args[i + 5] : nil
        Task {
            let quality = Double(dial ?? "").map { $0 / 100 }
            if let forecast = await FileConverter.estimateForSelfTest(
                source, shape: shape, fit: fit, compress: dial != "off",
                quality: quality ?? 0.55) {
                print("FORECAST: \(forecast) bytes")
            }
            let result = await FileConverter.reframeForSelfTest(
                source, to: outDir, shape: shape, fit: fit,
                compress: dial != "off", quality: quality)
            print(result.map { "SELFTEST OK: \($0.path)" } ?? "SELFTEST FAIL")
            exit(result == nil ? 1 : 0)
        }
    }
}
