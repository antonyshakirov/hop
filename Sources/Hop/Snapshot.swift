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

    static func runIfRequested() {
        let args = CommandLine.arguments

        // Dump of all temperature sensors — diagnoses sensor names on the specific chip.
        if args.contains("--sensors") {
            for (name, value) in HIDTemperatureReader().allSensors() {
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
                ("torrent-down", IconState(torrentDown: true)),
                ("torrent-both", IconState(torrentDown: true, torrentUp: true)),
                ("no-sleep+lid+engine", IconState(engine: .running, noSleep: true, lid: true)),
                ("worst", IconState(engine: .running, tracking: true, noSleep: true, lid: true,
                                    alertSteady: true, torrentDown: true, torrentUp: true)),
            ]
            let rowH: CGFloat = 26
            // two columns: coloured (dark bar) on the left, monochrome on the right
            let canvas = NSImage(size: NSSize(width: 340, height: CGFloat(variants.count) * rowH))
            canvas.lockFocus()
            NSColor(white: 0.1, alpha: 1).setFill()
            NSRect(origin: .zero, size: canvas.size).fill()
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
                    SettingsKey.canonicalLayoutSeeded, "moduleOrder",
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
            UserDefaults.standard.set(834.0, forKey: "speedLastDown")
            UserDefaults.standard.set(112.0, forKey: "speedLastUp")
            UserDefaults.standard.set(1450, forKey: "speedLastRpm")
            UserDefaults.standard.set(Date(), forKey: "speedLastAt")
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
            if let first = model.todos.list.items.first { model.todos.toggle(first.id) }
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

        var initial = PanelView.InitialScreen.spaceContaining("timer")
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
        if args.contains("--about") {
            initial = .about
        }

        // standalone windows: settings/about/converter
        let content: AnyView
        if args.contains("--window-settings") {
            content = AnyView(PanelView(initial: .settings, standaloneSettings: true).environmentObject(model))
        } else if args.contains("--window-about") {
            content = AnyView(PanelView(initial: .about, standaloneAbout: true).environmentObject(model))
        } else if args.contains("--window-converter") {
            content = AnyView(ConvertWindowView().environmentObject(model))
        } else if args.contains("--torrent-addsheet") {
            // Standalone render of the add sheet: the source here is a stand-in —
            // TorrentAddSheet swaps in demoAddSheetPending() under Snapshot.active
            // instead of calling fetchFiles, so no engine/network is touched.
            content = AnyView(TorrentAddSheet(source: .link("magnet:?xt=urn:btih:demo"), torrent: model.torrent) {})
        } else if args.contains("--onboarding") {
            // First-launch form (module choices incl. torrents) for design review.
            content = AnyView(
                OnboardingView(updater: model.updater, finish: {})
                    .padding(20)
                    .frame(width: 380)
                    .background(Theme.panelBackground)
            )
        } else {
            content = AnyView(PanelView(initial: initial).environmentObject(model))
        }
        let renderer = ImageRenderer(content: content)
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
    /// sites. Covers ALL 18 app locales: these flat-list modules are flagship
    /// 1.4.0 surfaces shown in per-locale marketing screenshots, so an English
    /// fallback here would be visible. English stays the defensive default. The
    /// staged totals/active/done state is applied by the caller, not here.
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
