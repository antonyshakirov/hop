import AppKit
import SwiftUI
import HopCore

/// Dev mode: `Hop --snapshot out.png` renders the panel to a PNG and exits.
/// Lets us look at the design without clicking the menu bar.
@MainActor
enum Snapshot {
    /// true during a dev render: ImageRenderer can't handle ScrollView,
    /// standalone screens are drawn without scrolling
    static var active = false

    /// Which info-window section a render opens on: "--news" for the release
    /// notes, "--permissions" for the permission list, "--doc <id>" for any
    /// module's help tab, the usual "general" otherwise. Snapshots only — the
    /// live app always opens on "general".
    static var aboutSectionForRender: String {
        guard active else { return "general" }
        let args = CommandLine.arguments
        if args.contains("--news") { return "news" }
        if args.contains("--permissions") { return "permissions" }
        if let i = args.firstIndex(of: "--doc"), args.count > i + 1 { return args[i + 1] }
        return "general"
    }

    /// Which settings section a render opens on: "--settings-section <id>".
    /// Snapshots only — the live app always opens on "general".
    static var settingsSectionForRender: String {
        guard active else { return "general" }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--settings-section"), args.count > i + 1 { return args[i + 1] }
        return "general"
    }

    static func runIfRequested() {
        let args = CommandLine.arguments

        // `Hop --uninstall-scan /Applications/Foo.app` prints what the uninstaller
        // would find, with sizes and flags, and exits. This is how the module is
        // checked against a real app — and against what other uninstallers claim
        // — without clicking through a window.
        if let i = args.firstIndex(of: "--uninstall-scan"), args.count > i + 1 {
            let path = args[i + 1]
            let bundle = Bundle(url: URL(fileURLWithPath: path))
            let name = FileManager.default.displayName(atPath: path)
                .replacingOccurrences(of: ".app", with: "")
            let id = UninstallController.resolvedIdentifier(
                provided: bundle?.bundleIdentifier ?? "", name: name)
            print("app: \(name)   id: \(id.isEmpty ? "—" : id)")
            var total: Int64 = 0
            for trace in UninstallController.scanTraces(identifier: id, name: name, appPath: path) {
                total += trace.bytes
                let flags = [trace.candidate.match == .identifier ? "id"
                                : (trace.candidate.match == .exactName ? "name" : "name?"),
                             trace.candidate.shared ? "SHARED" : nil,
                             AppUninstall.needsAdmin(path: trace.path, kind: trace.kind)
                                 ? "admin" : nil,
                             trace.ticked ? nil : "unticked"]
                    .compactMap { $0 }.joined(separator: " ")
                print(String(format: "%10.1f MB  %-16@ %-16@ %@",
                             Double(trace.bytes) / 1_048_576,
                             trace.kind.rawValue as NSString,
                             flags as NSString,
                             trace.path as NSString))
            }
            print(String(format: "total: %.1f MB", Double(total) / 1_048_576))
            exit(0)
        }

        // `Hop --uninstall-remove <app>` performs the same removal the window does,
        // from the terminal: quit, boot out the agents, move every ticked trace to
        // the TRASH. Dev-only like the other self-tests, and the way a comparison
        // is finished after another uninstaller has had its turn.
        if let i = args.firstIndex(of: "--uninstall-remove"), args.count > i + 1 {
            let path = args[i + 1]
            let name = FileManager.default.displayName(atPath: path)
                .replacingOccurrences(of: ".app", with: "")
            let id = UninstallController.resolvedIdentifier(
                provided: Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier ?? "",
                name: name)
            let traces = UninstallController.scanTraces(identifier: id, name: name, appPath: path)
                .filter(\.ticked)
            var moved = 0
            for trace in traces where !AppUninstall.needsAdmin(path: trace.path, kind: trace.kind) {
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: trace.path),
                                                     resultingItemURL: nil)
                    moved += 1
                    print("trashed: \(trace.path)")
                } catch {
                    print("FAILED : \(trace.path)")
                }
            }
            let admin = traces.filter { AppUninstall.needsAdmin(path: $0.path, kind: $0.kind) }
            if !admin.isEmpty {
                print("needs an administrator, left for the window: \(admin.count)")
            }
            print("moved \(moved) of \(traces.count) to the trash")
            exit(0)
        }

        // Dump of all temperature sensors — diagnoses sensor names on the specific chip.
        if args.contains("--sensors") {
            for (name, value) in TemperatureReader().allSensors() {
                print(String(format: "%6.1f  %@", value, name))
            }
            exit(0)
        }

        // Render the status bar icons in all states — a visual check of the
        // corner-badge system (both colour and monochrome).
        if let i = args.firstIndex(of: "--menubar-icons"), args.count > i + 1 {
            active = true // suppress the dev "D" so the badges are seen clean
            let variants: [(String, IconState)] = [
                ("idle", IconState()),
                ("engine", IconState(engine: .running)),
                ("task", IconState(tracking: true)),
                ("engine+task", IconState(engine: .running, tracking: true)),
                ("no-sleep", IconState(noSleep: true)),
                ("lid", IconState(lid: true)),
                ("no-sleep+lid", IconState(noSleep: true, lid: true)),
                ("alert", IconState(alertSteady: true)),
                ("vpn", IconState(vpn: .up)),
                ("vpn-stalled", IconState(vpn: .stalled)),
                ("no-sleep+vpn", IconState(noSleep: true, vpn: .up)),
                ("reminder+vpn", IconState(reminderUnseen: true, vpn: .up)),
                ("torrent-down", IconState(torrentDown: true)),
                ("vpn+torrent-down", IconState(vpn: .up, torrentDown: true)),
                ("vpn+torrent-both", IconState(vpn: .up, torrentDown: true, torrentUp: true)),
                ("vpn-stalled+torrent-both", IconState(vpn: .stalled, torrentDown: true, torrentUp: true)),
                ("torrent-both", IconState(torrentDown: true, torrentUp: true)),
                ("no-sleep+lid+engine", IconState(engine: .running, noSleep: true, lid: true)),
                ("worst", IconState(engine: .running, tracking: true, noSleep: true, lid: true,
                                    alertSteady: true, torrentDown: true, torrentUp: true)),
                ("worst+vpn", IconState(engine: .running, tracking: true, noSleep: true, lid: true,
                                        alertSteady: true, vpn: .up,
                                        torrentDown: true, torrentUp: true)),
            ]
            let rowH: CGFloat = 26
            // optional version stamp (short commit hash + timestamp) in a bottom
            // strip, so a saved sheet always says which build produced it. Passed in
            // via HOP_MENUBAR_LABEL — computed by the caller, since the binary has no
            // baked-in git hash.
            let stamp = ProcessInfo.processInfo.environment["HOP_MENUBAR_LABEL"]
            let stampH: CGFloat = stamp == nil ? 0 : 14
            // two columns: coloured (dark bar) on the left, monochrome on the right
            let canvas = NSImage(size: NSSize(width: 340, height: CGFloat(variants.count) * rowH + stampH))
            canvas.lockFocus()
            NSColor(white: 0.1, alpha: 1).setFill()
            NSRect(origin: .zero, size: canvas.size).fill()
            if let stamp {
                NSAttributedString(string: stamp, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.4),
                ]).draw(at: NSPoint(x: 8, y: 3))
            }
            for (index, v) in variants.enumerated() {
                let y = canvas.size.height - CGFloat(index + 1) * rowH + 4
                var colored = v.1; colored.colored = true
                var mono = v.1; mono.colored = false
                MenuBarIcon.compose(IconBadges.compose(colored), dark: true)
                    .draw(at: NSPoint(x: 8, y: y), from: .zero, operation: .sourceOver, fraction: 1)
                MenuBarIcon.compose(IconBadges.compose(mono), dark: true)
                    .draw(at: NSPoint(x: 200, y: y), from: .zero, operation: .sourceOver, fraction: 1)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.6),
                ]
                NSAttributedString(string: v.0, attributes: attrs)
                    .draw(at: NSPoint(x: 38, y: y + 3))
            }
            canvas.unlockFocus()
            if let tiff = canvas.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: args[i + 1]))
            }
            exit(0)
        }

        // `Hop --ocr-selftest <image>` prints what recognition makes of a file
        // and exits. The reference set for the two-pass merge lives in the specs;
        // this is how it is re-checked without a human dragging pictures around.
        if let i = args.firstIndex(of: "--ocr-selftest"), args.count > i + 1 {
            let url = URL(fileURLWithPath: args[i + 1])
            ScreenTextController.diagnostics = args.contains("--verbose")
            let started = Date()
            let text = ScreenTextController.recognizeForSelfTest(url)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            print("[\(ms) ms]")
            print(text ?? "(nothing recognized)")
            exit(text == nil ? 1 : 0)
        }

        if args.contains("--l10n-check") {
            let missing = L10n.missingKeys()
            print(missing.isEmpty ? "l10n: all translations present" : "l10n missing:\n" + missing.joined(separator: "\n"))
            exit(missing.isEmpty ? 0 : 1)
        }

        guard let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 else { return }
        let url = URL(fileURLWithPath: args[i + 1])
        active = true

        // language and theme for checking localization/layout: --lang de --theme light
        if let li = args.firstIndex(of: "--lang"), args.count > li + 1 {
            UserDefaults.standard.set(args[li + 1], forKey: SettingsKey.appLanguage)
        }
        if let ti = args.firstIndex(of: "--theme"), args.count > ti + 1 {
            UserDefaults.standard.set(args[ti + 1], forKey: Theme.themeKey)
            Theme.systemDark = args[ti + 1] != "light"
        }

        // The screenshot locale — drives every localized demo string below
        // (clipboard long text, tracker/to-do demo content). English by default.
        let demoLang = args.firstIndex(of: "--lang").flatMap { i in
            args.count > i + 1 ? args[i + 1] : nil
        } ?? "en"

        // Clean module layout per render: snapshots share the dev bundle's
        // UserDefaults, and visibility is membership now (the inactive bucket).
        // Clear the persisted spaces + the one-shot migration flags + the legacy
        // toggles so `loadTabs` migrates fresh from the keys THIS run sets
        // (below, e.g. --torrents), instead of decoding a prior render's layout.
        for key in [SettingsKey.panelTabs, SettingsKey.moduleVisibilityMigrated,
                    SettingsKey.trackerTabSeeded, SettingsKey.todosSeeded,
                    SettingsKey.canonicalLayoutSeeded, SettingsKey.optInModulesSeeded,
                    SettingsKey.optInModulesSeeded170,
                    "moduleOrder",
                    "showTimerModule", "showAwakeModule", "showClipboardModule",
                    "showConvertModule", "showWindowsModule", "showSpeedtestModule",
                    "showSystemModule", "showTrackerModule", "showTorrentModule"] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // --demo: staged state for product-page screenshots — clipboard rows
        // and a fresh speed-test result, seeded through the regular
        // UserDefaults keys BEFORE AppModel is created so the controllers
        // pick them up on init.
        if args.contains("--demo") {
            struct DemoItem: Codable { let id: UUID; let text: String }
            // a link + a file path + a long text (truncated by the row);
            // the long text is localized to the screenshot language
            let longText: String
            switch demoLang {
            case "ru": longText = "перепиши этот текст короче и проще, сохрани дружелюбный тон и добавь в конце призыв к действию"
            case "de": longText = "schreib den text kürzer und einfacher, behalte den freundlichen ton und ende mit einem call-to-action"
            case "fr": longText = "réécris ce texte plus court et plus simple, garde le ton amical et termine par un appel à l'action"
            case "es": longText = "reescribe este texto más corto y simple, mantén el tono cercano y termina con una llamada a la acción"
            case "pt": longText = "reescreve este texto mais curto e simples, mantém o tom amigável e termina com uma chamada para ação"
            case "zh": longText = "把这段文字改得更短更简单，保持友好的语气，结尾加一句行动号召"
            case "ja": longText = "この文章をもっと短くシンプルに書き直して、親しみやすいトーンのまま、最後に行動を促す一文を"
            default: longText = "rewrite this text shorter and simpler, keep the friendly tone and end with a call to action"
            }
            let demoItems = [
                DemoItem(id: UUID(), text: "https://antonshakirov.com/products/hop"),
                DemoItem(id: UUID(), text: "~/Documents/design-tokens.css"),
                DemoItem(id: UUID(), text: longText),
            ]
            if let data = try? JSONEncoder().encode(demoItems) {
                UserDefaults.standard.set(data, forKey: "clipboardHistory")
            }
            // The overview shot shows every module at once, so no row may look
            // dead in it: the colour picker reads its swatches out of the same
            // history the clipboard uses (a picked colour IS an entry), and
            // without any it says "no colors yet" in the one picture meant to
            // show what the app does.
            //
            // The colours therefore go BELOW the three visible rows: the clipboard
            // list shows three by default, and a shot whose clipboard is all
            // swatches says "this keeps colours" twice over while never showing
            // that it keeps a link, a file and a piece of text (Anton, 2026-07-30).
            if args.contains("--overview") {
                let mixed: [ClipboardItem] = [
                    ClipboardItem(text: "https://antonshakirov.com/products/hop"),
                    ClipboardItem(text: "~/Documents/design-tokens.css"),
                    ClipboardItem(text: longText),
                    ClipboardItem(text: "#2F6D5B", colorHex: "2F6D5B"),
                    ClipboardItem(text: "#E8DCC8", colorHex: "E8DCC8"),
                ]
                if let data = try? JSONEncoder().encode(mixed) {
                    UserDefaults.standard.set(data, forKey: "clipboardHistory")
                }
            }
            UserDefaults.standard.set(834.0, forKey: "speedLastDown")
            UserDefaults.standard.set(112.0, forKey: "speedLastUp")
            UserDefaults.standard.set(1450, forKey: "speedLastRpm")
            UserDefaults.standard.set(Date(), forKey: "speedLastAt")
        }

        // Every module's legacy visibility toggle, by module id. Setting one to
        // false is what the isolation flags below use to empty the panel around
        // the module a shot is about.
        let moduleKeys = [
            "timer": "showTimerModule", "awake": "showAwakeModule",
            "clipboard": "showClipboardModule", "convert": "showConvertModule",
            "windows": "showWindowsModule", "speed": "showSpeedtestModule",
            "system": "showSystemModule", "tracker": "showTrackerModule",
            "torrent": "showTorrentModule",
        ]

        // --only <id>: leave ONE module's row on the panel and hide everything
        // else. A section of the README (or of the product page) is about a
        // single module, and a shot of the whole panel next to it shows the
        // reader nine other things instead of the one being described — the
        // timer section carried a picture of the entire app (Anton, 2026-07-28).
        // The older per-module flags stay: they stage content as well, which
        // this one does not need beyond --demo.
        let onlyModule: String? = args.firstIndex(of: "--only").flatMap {
            args.count > $0 + 1 ? args[$0 + 1] : nil
        }
        if let onlyModule {
            for (id, key) in moduleKeys where id != onlyModule {
                UserDefaults.standard.set(false, forKey: key)
            }
        }

        // --overview: the opposite of --only — every module at once, the opt-in
        // ones included, for the single shot at the top of the README that has
        // to answer "what is this app" before any section explains a part of it.
        let wantsOverview = args.contains("--overview")

        // --colors / --ocr / --tools: isolate the opt-in tool modules (the
        // eyedropper, screen text, or both) with a staged swatch strip. They ship
        // hidden, so they are activated explicitly after the model exists (below)
        // — the fresh migrate this render takes always hides them.
        let wantsColors = args.contains("--colors") || args.contains("--tools")
        let wantsOcr = args.contains("--ocr") || args.contains("--tools")
        if wantsColors || wantsOcr {
            for key in ["showTimerModule", "showAwakeModule", "showConvertModule",
                        "showWindowsModule", "showSpeedtestModule", "showSystemModule",
                        "showTrackerModule"] {
                UserDefaults.standard.set(false, forKey: key)
            }
            // A picked color IS a clipboard entry, so the strip and the shelf are
            // staged by the same key — real entries, not a special demo path.
            let staged = [
                ClipboardItem(text: "#2F6D5B", colorHex: "2F6D5B"),
                ClipboardItem(text: "#E8DCC8", colorHex: "E8DCC8"),
                ClipboardItem(text: "#1B1B1F", colorHex: "1B1B1F"),
                ClipboardItem(text: "#C7452B", colorHex: "C7452B"),
                ClipboardItem(text: "#7A8FA6", colorHex: "7A8FA6"),
            ]
            if let data = try? JSONEncoder().encode(staged) {
                UserDefaults.standard.set(data, forKey: "clipboardHistory")
            }
        }

        // --keyboard: isolate the cleaning-mode row, the way --archive isolates
        // the archive one — the marketing shot is about that single line.
        let wantsKeyboard = args.contains("--keyboard")
        if wantsKeyboard {
            for key in ["showTimerModule", "showAwakeModule", "showClipboardModule",
                        "showConvertModule", "showWindowsModule", "showSpeedtestModule",
                        "showSystemModule", "showTrackerModule"] {
                UserDefaults.standard.set(false, forKey: key)
            }
        }

        // --archive: isolate the archive module with a couple of settled rows,
        // so the drop zone, the format chips and the result rows render together.
        let wantsArchive = args.contains("--archive")
        if wantsArchive {
            for key in ["showTimerModule", "showAwakeModule", "showClipboardModule",
                        "showConvertModule", "showWindowsModule", "showSpeedtestModule",
                        "showSystemModule", "showTrackerModule"] {
                UserDefaults.standard.set(false, forKey: key)
            }
        }

        // --torrents: isolate the torrent module (hide the others) so its state
        // renders on its own. Variants: --torrents-collapsed folds the list to the
        // header, --torrents-empty renders the empty add-card (no rows injected),
        // --torrents-firstrun forces the one-time default-handler banner back on,
        // --torrents-states adds the files-removed row (design review; the plain
        // --torrents render stays clean for the landing screenshots).
        let wantsTorrents = args.contains("--torrents")
            || args.contains("--torrents-collapsed")
            || args.contains("--torrents-empty")
            || args.contains("--torrents-firstrun")
            || args.contains("--torrents-states")
        if wantsTorrents {
            for key in ["showTimerModule", "showAwakeModule", "showClipboardModule",
                        "showConvertModule", "showWindowsModule", "showSpeedtestModule"] {
                UserDefaults.standard.set(false, forKey: key)
            }
            UserDefaults.standard.set(true, forKey: "showTorrentModule")
            UserDefaults.standard.set("torrent", forKey: "moduleOrder")
            // Reset the persisted keys explicitly — snapshot runs share the dev
            // bundle's UserDefaults, so a prior variant must not leak in.
            UserDefaults.standard.set(args.contains("--torrents-collapsed"), forKey: "torrentCollapsed")
            UserDefaults.standard.set(true, forKey: TorrentController.showWhenEmptyKey)
            // Default to "already prompted" (banner hidden) so the plain empty/list
            // renders stay clean; --torrents-firstrun flips it back to unprompted.
            UserDefaults.standard.set(!args.contains("--torrents-firstrun"), forKey: "torrentDefaultHandlerPrompted")
        }

        let model = AppModel()
        if wantsTorrents, !args.contains("--torrents-empty") {
            model.torrent.loadDemo(demoTorrents(includeMissing: args.contains("--torrents-states")))
        }
        // --tasks: seed the tracker + to-do modules and open the space that
        // stacks them, so a snapshot shows both flat lists (subheaders, flush
        // rows). Demo content is localized per screenshot locale (see demoTasks).
        if args.contains("--tasks") {
            let e = model.tracker.engine
            // The load path is already gated on Snapshot.active (empty), but wipe
            // defensively so the seed renders the same every time regardless.
            for id in e.data.rootOrder { e.deleteTask(id) }
            for item in model.todos.list.items { model.todos.delete(item.id) }
            let content = demoTasks(lang: demoLang)
            for name in content.tasks { e.addTask(name: name) }
            let ids = e.data.rootOrder
            if ids.count == 3 {
                e.setTotal(taskID: ids[0], to: 2 * 3600 + 12 * 60)   // 2:12
                e.setTotal(taskID: ids[1], to: 5 * 3600 + 3 * 60)    // ticks while active
                e.setTotal(taskID: ids[2], to: 47 * 60)              // 47m
                e.start(taskID: ids[1])                              // active row: emphasized total
            }
            for text in content.todos { model.todos.add(text: text) }
            let todoIDs = model.todos.list.items.map(\.id)
            if let first = todoIDs.first { model.todos.toggle(first) }
            // Show the row's two marks in screenshots: one task carries a note,
            // one is a favourite with a reminder. Deterministic values only —
            // a screenshot must render the same on any machine on any day.
            if todoIDs.count >= 3 {
                // The note text is borrowed from the same localized set rather
                // than adding a 22-case string of its own: a screenshot only has
                // to show that a note EXISTS and reads in the right language.
                model.todos.setNote(todoIDs[1], to: content.tasks.first ?? "")
                model.todos.setImportant(todoIDs[2], true)
                var when = DateComponents()
                when.year = 2026; when.month = 7; when.day = 28
                when.hour = 15; when.minute = 0
                if let date = Calendar.current.date(from: when) {
                    model.todos.setReminder(todoIDs[2], at: date, repeatDays: [])
                }
            }
        }
        // --convert-files a,b,c: converter queue for the window screenshot;
        // the pause lets thumbnails and size estimates finish (they're async)
        if let ci = args.firstIndex(of: "--convert-files"), args.count > ci + 1 {
            let urls = args[ci + 1].split(separator: ",").map { URL(fileURLWithPath: String($0)) }
            model.converter.addToBatch(urls)
            RunLoop.main.run(until: Date().addingTimeInterval(3.0))
        }
        if args.contains("--finished") {
            model.engine.start()
            model.engine.adjust(by: -(model.engine.duration + 1))
        }
        if args.contains("--running") {
            model.engine.start()
        }
        if args.contains("--stash") {
            model.engine.start()
            model.engine.setPreset(minutes: 30)
        }
        if args.contains("--awake") {
            model.keepAwake.activate(KeepAwakeController.options[1]) // 30 minutes
        }

        if wantsArchive {
            model.archive.loadDemo([
                .init(kind: .extract, name: "sprint-42-assets.zip", state: .done("/tmp/sprint-42-assets")),
                .init(kind: .pack, name: "raw-shoot.tar.gz", state: .running),
            ])
        }
        // The window shots need the queue as well: the button is the whole point
        // of the module now, and an empty window would not show it.
        if args.contains("--window-archive"), args.contains("--demo") {
            model.archive.loadDemo([], pending: [
                URL(fileURLWithPath: "/Users/demo/Desktop/sprint-42-assets.zip"),
                URL(fileURLWithPath: "/Users/demo/Desktop/press-kit.7z"),
            ])
        }
        if args.contains("--window-ocr"), args.contains("--demo") {
            model.screenText.loadDemo(demoRecognizedText(lang: demoLang))
        }
        // One module per shot: the isolation flags hide the OTHER new modules as
        // well, or a colour-picker render comes out with archives and the
        // keyboard lock stacked above it.
        if wantsColors || wantsOcr || wantsKeyboard || wantsArchive
            || onlyModule != nil || wantsOverview {
            var keep: Set<String> = []
            if wantsOverview {
                keep = ["color", "ocr", "keyboard", "archive", "vpn", "uninstall"]
            }
            if wantsColors { keep.insert("color") }
            if wantsOcr { keep.insert("ocr") }
            if wantsKeyboard { keep.insert("keyboard") }
            if wantsArchive { keep.insert("archive") }
            // no-op unless --only names one of these four; the rest are hidden
            // through their legacy keys above
            if let onlyModule { keep.insert(onlyModule) }
            for key in ["color", "ocr", "keyboard", "archive", "vpn", "uninstall"] {
                if keep.contains(key) {
                    PanelView.activateStoredModule(key)
                } else {
                    PanelView.deactivateStoredModule(key)
                }
            }
        }

        // A grid of apps has no fixed key — it carries the demo shelf's id, minted
        // a moment ago — so `--only apps` resolves to that key and places it.
        var appsKey: String?
        if onlyModule == "apps" || wantsOverview, let key = model.appShelves.shelves.moduleKeys.first {
            appsKey = key
            PanelView.introduceStoredModule(key)
        }

        var initial = PanelView.InitialScreen.spaceContaining("timer")
        if let appsKey, onlyModule == "apps" {
            initial = .spaceContaining(appsKey)
        } else if let onlyModule {
            initial = .spaceContaining(onlyModule)
        } else if wantsKeyboard {
            initial = .spaceContaining("keyboard")
        } else if wantsArchive {
            initial = .spaceContaining("archive")
        } else if wantsColors {
            initial = .spaceContaining("color")
        } else if wantsOcr {
            initial = .spaceContaining("ocr")
        }
        if args.contains("--stats") {
            initial = .spaceContaining("system")
            model.stats.refresh() // primes the deltas
            usleep(600_000)
            model.stats.refresh()
            // --charts: the detailed mode with live graphs. History is
            // synthesized (sin-based, deterministic): a real run only has
            // two points by render time and the charts would come out empty
            UserDefaults.standard.set(args.contains("--charts"), forKey: "monitorDetailed")
            if args.contains("--charts") {
                var demo = SystemStatsController.History()
                let now = Date()
                for i in stride(from: 300, through: 0, by: -5) {
                    let t = now.addingTimeInterval(-Double(i))
                    let x = Double(300 - i) / 300 * .pi * 6
                    demo.cpuLoad.append(.init(t: t, v: 0.32 + 0.16 * sin(x) + 0.09 * sin(x * 2.7)))
                    demo.cpuTemp.append(.init(t: t, v: 49 + 6 * sin(x * 0.8 + 1)))
                    demo.memShare.append(.init(t: t, v: 0.72 + 0.035 * sin(x * 0.5 + 0.6)))
                    demo.netDown.append(.init(t: t, v: max(0, 950_000 + 780_000 * sin(x * 1.3) + 550_000 * sin(x * 3.1))))
                    demo.netUp.append(.init(t: t, v: max(0, 230_000 + 170_000 * sin(x * 1.7 + 2))))
                }
                model.stats.injectDemoHistory(demo)
            }
        }
        if args.contains("--tasks") {
            initial = .spaceContaining("tracker")
        }
        if args.contains("--settings") {
            initial = .settings
        }
        if args.contains("--about") || args.contains("--permissions") {
            initial = .about
        }

        // standalone windows: settings/about/converter
        let content: AnyView
        if args.contains("--window-settings") {
            content = AnyView(PanelView(initial: .settings, standaloneSettings: true).environmentObject(model))
        } else if args.contains("--window-about") {
            // WIDTH pinned to the window's own 1060: the standalone about is a
            // ScrollView with maxHeight .infinity, and ImageRenderer handed that
            // an unbounded height, so the render came out blank. With the width
            // fixed the content reports its natural height, which is also how
            // this render doubles as a measurement of what the window must fit.
            content = AnyView(PanelView(initial: .about, standaloneAbout: true)
                .environmentObject(model)
                .frame(width: 1060))
        } else if args.contains("--window-converter") {
            content = AnyView(ConvertWindowView().environmentObject(model))
        } else if args.contains("--window-archive") {
            content = AnyView(ArchiveWindowView().environmentObject(model)
                .frame(width: 480))
        } else if args.contains("--window-archive-progress") {
            let first = UUID()
            let second = UUID()
            let progress = FinderArchiveProgressModel(files: [
                (id: first, fileName: "sprint-42-assets.zip"),
                (id: second, fileName: "damaged-reference-files.7z"),
            ])
            progress.receive(.failed(.tool), for: second)
            content = AnyView(
                FinderArchiveProgressView(model: progress, lang: L10n.current))
        } else if args.contains("--window-uninstall") || args.contains("--window-clean") {
            // The uninstaller's two jobs. Staged rather than scanned: the real
            // lists are this Mac's own apps and this Mac's own disk, and a
            // product shot must not be somebody's home folder.
            model.uninstall.stageDemo(args.contains("--window-clean") ? .clean : .uninstall)
            content = AnyView(UninstallWindowView(uninstall: model.uninstall,
                                                  lang: L10n.current)
                .environmentObject(model)
                // A ScrollView inside ImageRenderer needs a height to render at
                // all — unbounded, it reports nothing and the picture comes out
                // empty, the same trap the about window fell into.
                .frame(width: args.contains("--window-clean") ? 620 : 560,
                       height: args.contains("--window-clean") ? 900 : 620))
        } else if args.contains("--window-ocr") {
            content = AnyView(ScreenTextWindowView().environmentObject(model)
                .frame(width: 560))
        } else if args.contains("--torrent-addsheet") {
            // Standalone render of the add sheet: the source here is a stand-in —
            // TorrentAddSheet swaps in demoAddSheetPending() under Snapshot.active
            // instead of calling fetchFiles, so no engine/network is touched.
            content = AnyView(TorrentAddSheet(source: .link("magnet:?xt=urn:btih:demo"), torrent: model.torrent) {})
        } else if args.contains("--onboarding") {
            // First-launch form (module choices incl. torrents) for design review.
            content = AnyView(
                OnboardingView(updater: model.updater, shelves: model.appShelves, finish: {})
                    .padding(20)
                    .frame(width: 600)
                    .background(Theme.panelBackground)
            )
        } else {
            content = AnyView(PanelView(initial: initial).environmentObject(model))
        }
        // Same direction the real windows get, so `--lang ar` renders a
        // right-to-left panel instead of Arabic text in a left-to-right shell.
        let renderer = ImageRenderer(content: content.hopLayoutDirection())
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            fputs("snapshot render failed\n", stderr)
            exit(1)
        }
        try? png.write(to: url)
        exit(0)
    }

    /// Localized tracker + to-do demo content for the `--tasks` snapshot (three
    /// tasks, three to-dos) — one of the sanctioned per-locale screenshot string
    /// sites. Covers ALL 22 app locales: these flat-list modules are flagship
    /// 1.4.0 surfaces shown in per-locale marketing screenshots, so an English
    /// fallback here would be visible. English stays the defensive default. The
    /// staged totals/active/done state is applied by the caller, not here.
    /// A believable recognition result for the marketing shot: a few lines of a
    /// receipt-like text, in the screenshot's own language.
    static func demoRecognizedText(lang: String) -> String {
        switch lang {
        case "ru":
            return "конференция «дизайн-системы»\n12 сентября, 10:00\nул. Рочдельская, 15, стр. 17\nбилет №A-2416 · место 12"
        case "de":
            return "konferenz «design-systeme»\n12. september, 10:00\nrochdelskaja 15, haus 17\nticket nr. A-2416 · platz 12"
        case "fr":
            return "conférence « design systems »\n12 septembre, 10:00\n15 rue Rochdelskaïa, bât. 17\nbillet n° A-2416 · place 12"
        case "es":
            return "conferencia «design systems»\n12 de septiembre, 10:00\ncalle Rochdelskaya 15, edificio 17\nentrada n.º A-2416 · asiento 12"
        case "pt":
            return "conferência «design systems»\n12 de setembro, 10:00\nrua Rochdelskaya 15, bloco 17\ningresso n.º A-2416 · assento 12"
        case "zh":
            return "「设计系统」大会\n9 月 12 日 10:00\n罗奇杰利斯卡娅街 15 号 17 栋\n票号 A-2416 · 座位 12"
        case "ja":
            return "カンファレンス「デザインシステム」\n9月12日 10:00\nロチデリスカヤ通り15号館17\nチケット番号 A-2416 ・ 座席 12"
        case "ar":
            return "مؤتمر «أنظمة التصميم»\n12 سبتمبر، 10:00\nشارع روتشديلسكايا 15، مبنى 17\nتذكرة رقم A-2416 · مقعد 12"
        case "he":
            return "כנס «מערכות עיצוב»\n12 בספטמבר, 10:00\nרחוב רוצ׳דלסקאיה 15, בניין 17\nכרטיס מס׳ A-2416 · מושב 12"
        case "fa":
            return "همایش «سامانه‌های طراحی»\n۱۲ سپتامبر، ۱۰:۰۰\nخیابان روچدلسکایا ۱۵، ساختمان ۱۷\nبلیت شمارهٔ A-2416 · صندلی ۱۲"
        case "ur":
            return "کانفرنس «ڈیزائن سسٹمز»\n۱۲ ستمبر، ۱۰:۰۰\nروچدیلسکایا اسٹریٹ ۱۵، عمارت ۱۷\nٹکٹ نمبر A-2416 · نشست ۱۲"
        default:
            return "«design systems» conference\nseptember 12, 10:00\n15 Rochdelskaya st., bldg 17\nticket no. A-2416 · seat 12"
        }
    }

    static func demoTasks(lang: String) -> (tasks: [String], todos: [String]) {
        switch lang {
        case "ru":
            return (["написать пост к запуску", "разобрать пул-реквесты", "набросать строки трекера"],
                    ["выкатить плоский трекер", "синхронизировать доки и тесты", "взять билеты на офсайт"])
        case "de":
            return (["launch-post schreiben", "pull requests prüfen", "tracker-zeilen skizzieren"],
                    ["flachen tracker ausliefern", "docs und tests abgleichen", "flüge fürs offsite buchen"])
        case "fr":
            return (["écrire le post de lancement", "relire les pull requests", "esquisser les lignes du tracker"],
                    ["livrer le tracker à plat", "synchroniser docs et tests", "réserver les vols pour l'offsite"])
        case "es":
            return (["escribir el post de lanzamiento", "revisar los pull requests", "bocetar las filas del tracker"],
                    ["lanzar el tracker plano", "sincronizar docs y tests", "reservar vuelos para el offsite"])
        case "pt":
            return (["escrever o post de lançamento", "revisar os pull requests", "esboçar as linhas do tracker"],
                    ["lançar o tracker plano", "sincronizar docs e testes", "reservar voos para o offsite"])
        case "zh":
            return (["写发布贴文", "审查合并请求", "勾画跟踪器行"],
                    ["发布扁平跟踪器", "同步文档和测试", "预订团建机票"])
        case "ja":
            return (["ローンチ投稿を書く", "プルリクをレビュー", "トラッカーの行を下描き"],
                    ["フラットなトラッカーを出す", "ドキュメントとテストを同期", "オフサイトの航空券を予約"])
        case "it":
            return (["scrivere il post di lancio", "revisionare le pull request", "abbozzare le righe del tracker"],
                    ["rilasciare il tracker piatto", "sincronizzare docs e test", "prenotare i voli per l'offsite"])
        case "ko":
            return (["출시 글 작성하기", "풀 리퀘스트 검토하기", "트래커 행 스케치하기"],
                    ["플랫 트래커 출시하기", "문서와 테스트 동기화하기", "오프사이트 항공권 예약하기"])
        case "tr":
            return (["lansman yazısını yaz", "pull request'leri incele", "tracker satırlarını taslakla"],
                    ["düz tracker'ı yayınla", "dokümanları ve testleri eşitle", "offsite için uçuşları ayır"])
        case "uk":
            return (["написати пост до запуску", "розібрати пул-реквести", "накидати рядки трекера"],
                    ["випустити плоский трекер", "синхронізувати доки й тести", "взяти квитки на офсайт"])
        case "pl":
            return (["napisać post premierowy", "przejrzeć pull requesty", "naszkicować wiersze trackera"],
                    ["wydać płaski tracker", "zsynchronizować dokumenty i testy", "zarezerwować loty na offsite"])
        case "id":
            return (["tulis postingan peluncuran", "tinjau pull request", "sketsa baris tracker"],
                    ["rilis tracker datar", "sinkronkan dokumen dan tes", "pesan tiket pesawat untuk offsite"])
        case "th":
            return (["เขียนโพสต์เปิดตัว", "รีวิวพูลรีเควสต์", "ร่างแถวแทร็กเกอร์"],
                    ["ปล่อยแทร็กเกอร์แบบแบน", "ซิงก์เอกสารและเทสต์", "จองตั๋วบินไปออฟไซต์"])
        case "vi":
            return (["viết bài đăng ra mắt", "duyệt các pull request", "phác thảo các hàng tracker"],
                    ["phát hành tracker phẳng", "đồng bộ tài liệu và test", "đặt vé máy bay cho offsite"])
        case "hi":
            return (["लॉन्च पोस्ट लिखें", "पुल रिक्वेस्ट रिव्यू करें", "ट्रैकर पंक्तियाँ स्केच करें"],
                    ["फ्लैट ट्रैकर रिलीज़ करें", "डॉक्स और टेस्ट सिंक करें", "ऑफसाइट के लिए फ्लाइट बुक करें"])
        case "nl":
            return (["lanceringspost schrijven", "pull requests beoordelen", "trackerrijen schetsen"],
                    ["de platte tracker uitbrengen", "docs en tests synchroniseren", "vluchten voor de offsite boeken"])
        case "ar":
            return (["كتابة منشور الإطلاق", "مراجعة طلبات الدمج", "تخطيط صفوف المتتبّع"],
                    ["إطلاق المتتبّع المسطّح", "مزامنة الوثائق والاختبارات", "حجز تذاكر رحلة الفريق"])
        case "he":
            return (["לכתוב את פוסט ההשקה", "לעבור על הפול ריקווסטים", "לשרטט את שורות המעקב"],
                    ["להוציא את המעקב השטוח", "לסנכרן תיעוד ובדיקות", "להזמין טיסות לאופסייט"])
        case "fa":
            return (["نوشتن پست عرضه", "بازبینی درخواست‌های ادغام", "طرح ردیف‌های ردیاب"],
                    ["عرضهٔ ردیاب ساده", "همگام‌سازی سندها و آزمون‌ها", "رزرو بلیت سفر تیمی"])
        case "ur":
            return (["لانچ پوسٹ لکھیں", "پل ریکویسٹ دیکھیں", "ٹریکر کی قطاریں خاکہ کریں"],
                    ["سادہ ٹریکر جاری کریں", "دستاویزات اور ٹیسٹ ہم آہنگ کریں", "آف سائٹ کے لیے ٹکٹ بک کریں"])
        default:
            return (["write launch post", "review pull requests", "sketch tracker rows"],
                    ["ship the flat tracker", "sync docs and tests", "book flights for the offsite"])
        }
    }

    /// Staged torrents for the `--torrents` list snapshot, covering the mixed
    /// states a review pass needs to see side by side:
    /// (a) downloading, with a LONG name to show the row's middle-truncation;
    /// (b) paused (engine-reported `.paused`) — resume glyph, 0/0 speeds, no eta;
    /// (c) done — green ✓, the reveal-in-Finder action, and the ↑ seed line;
    /// (d) files-removed (only with `includeMissing`, i.e. --torrents-states) —
    ///     payload deleted from disk under the download: the folder-badge glyph,
    ///     the red "files removed" line, and the resume glyph.
    private static func demoTorrents(includeMissing: Bool) -> [TorrentController.TorrentItem] {
        let isoFile = TorrentFile(
            index: 0, name: "ubuntu-24.04.1-desktop-amd64-verylongdescriptivereleasename.iso",
            lengthBytes: 4_825_000_000, selected: true)
        let downloading = TorrentController.TorrentItem(
            id: "1", infoHash: "aa11",
            name: "Ubuntu 24.04.1 LTS Desktop amd64 (very long descriptive release name).iso",
            files: [isoFile], outputFolder: "/tmp",
            stats: TorrentStats(
                state: .live, progressBytes: 3_136_250_000, totalBytes: 4_825_000_000,
                uploadedBytes: 40_000_000, downloadBps: 4_200_000, uploadBps: 128_000,
                peersLive: 22, peersSeen: 88, etaSeconds: 130, finished: false,
                fileProgressBytes: [3_136_250_000]))

        let iso2 = TorrentFile(index: 0, name: "debian-13.6.0-live-amd64.iso", lengthBytes: 1_400_000_000, selected: true)
        let sums = TorrentFile(index: 1, name: "SHA256SUMS", lengthBytes: 320_000, selected: true)
        let paused = TorrentController.TorrentItem(
            id: "2", infoHash: "bb22", name: "debian-13.6.0-live-amd64",
            files: [iso2, sums], outputFolder: "/tmp",
            stats: TorrentStats(
                state: .paused, progressBytes: 630_144_000, totalBytes: 1_400_320_000,
                uploadedBytes: 12_000_000, downloadBps: 0, uploadBps: 0,
                peersLive: 0, peersSeen: 74, etaSeconds: nil, finished: false,
                fileProgressBytes: [630_000_000, 144_000]))

        let iso = TorrentFile(index: 0, name: "ubuntu-24.04.iso", lengthBytes: 5_100_000_000, selected: true)
        let done = TorrentController.TorrentItem(
            id: "3", infoHash: "cc33", name: "ubuntu-24.04-desktop-amd64",
            files: [iso], outputFolder: "/tmp",
            stats: TorrentStats(
                state: .live, progressBytes: 5_100_000_000, totalBytes: 5_100_000_000,
                uploadedBytes: 5_100_000_000, downloadBps: 0, uploadBps: 256_000,
                peersLive: 5, peersSeen: 210, etaSeconds: nil, finished: true,
                fileProgressBytes: [5_100_000_000]))

        var missing = TorrentController.TorrentItem(
            id: "4", infoHash: "dd44", name: "fedora-workstation-42-live",
            files: [TorrentFile(index: 0, name: "Fedora-Workstation-Live-x86_64-42.iso", lengthBytes: 2_000_000_000, selected: true),
                    TorrentFile(index: 1, name: "Fedora-Workstation-42-CHECKSUM", lengthBytes: 2_100, selected: true)],
            outputFolder: "/tmp",
            stats: TorrentStats(
                state: .live, progressBytes: 1_500_000_000, totalBytes: 4_100_000_000,
                uploadedBytes: 8_000_000, downloadBps: 0, uploadBps: 0,
                peersLive: 0, peersSeen: 40, etaSeconds: nil, finished: false,
                fileProgressBytes: [1_500_000_000, 0]))
        missing.filesMissing = true
        missing.optimisticPaused = true   // the probe pauses it the instant it fires

        return includeMissing ? [downloading, paused, done, missing] : [downloading, paused, done]
    }

    /// Demo file list for the `--torrent-addsheet` snapshot: a multi-file
    /// pack (long ISO names + small extras), sizes mixed, two files
    /// deselected — so the checklist, the select-all/none chips, and the
    /// free-space math all render without an engine round trip. Content is
    /// deliberately open-source: torrents ARE the official channel for
    /// Linux images, and nothing here can read as a pirated release.
    static func demoAddSheetPending() -> (pending: TorrentController.PendingAdd, selected: Set<Int>) {
        let files = [
            TorrentFile(index: 0, name: "ubuntu-24.04.1-desktop-amd64.iso", lengthBytes: 6_100_000_000, selected: true),
            TorrentFile(index: 1, name: "kubuntu-24.04.1-desktop-amd64.iso", lengthBytes: 4_400_000_000, selected: true),
            TorrentFile(index: 2, name: "xubuntu-24.04.1-desktop-amd64.iso", lengthBytes: 4_100_000_000, selected: true),
            TorrentFile(index: 3, name: "ubuntu-24.04.1-live-server-amd64.iso", lengthBytes: 2_700_000_000, selected: false),
            TorrentFile(index: 4, name: "SHA256SUMS", lengthBytes: 1_300, selected: false),
            TorrentFile(index: 5, name: "README.txt", lengthBytes: 4_200, selected: true),
        ]
        let pending = TorrentController.PendingAdd(
            source: .link("magnet:?xt=urn:btih:demo"),
            name: "ubuntu-24.04.1-family-amd64",
            files: files)
        let selected = Set(files.filter { $0.selected }.map { $0.index })
        return (pending, selected)
    }
}

/// A list that scrolls in the app and simply stands still in a snapshot.
///
/// ImageRenderer hands a ScrollView an unbounded height, the ScrollView reports
/// nothing back, and the picture comes out empty — which is how a window full of
/// rows rendered as a title on black. In a snapshot the rows are laid out
/// directly instead, and the render is given a height by its caller.
struct SnapshotAwareScroll<Content: View>: View {
    var maxHeight: CGFloat?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if Snapshot.active {
            VStack(alignment: .leading, spacing: 0) { content() }
        } else if let maxHeight {
            ScrollView(showsIndicators: true) { content() }.frame(maxHeight: maxHeight)
        } else {
            ScrollView(showsIndicators: true) { content() }
        }
    }
}

// ImageRenderer can't render onDrop (it paints a yellow fill + 🚫),
// so snapshots simply drop the modifier.
import UniformTypeIdentifiers
extension View {
    @ViewBuilder
    func snapshotAwareDrop(
        of types: [UTType],
        isTargeted: Binding<Bool>?,
        perform action: @escaping ([NSItemProvider]) -> Bool
    ) -> some View {
        if Snapshot.active {
            self
        } else {
            self.onDrop(of: types, isTargeted: isTargeted, perform: action)
        }
    }
}
