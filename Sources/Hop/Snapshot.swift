import AppKit
import SwiftUI

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

        // Render the status bar icons in all states — a visual check of the badges.
        if let i = args.firstIndex(of: "--menubar-icons"), args.count > i + 1 {
            let variants: [(String, MenuBarIcon.StateBadge?, NSColor?)] = [
                ("idle", nil, nil),
                ("running", .running, nil),
                ("paused", .paused, nil),
                ("idle+awake", nil, .systemYellow),
                ("running+awake", .running, .systemYellow),
                ("lid-only", nil, .systemOrange),
            ]
            let canvas = NSImage(size: NSSize(width: 130, height: CGFloat(variants.count) * 26))
            canvas.lockFocus()
            NSColor(white: 0.1, alpha: 1).setFill()
            NSRect(origin: .zero, size: canvas.size).fill()
            for (index, v) in variants.enumerated() {
                let y = canvas.size.height - CGFloat(index + 1) * 26 + 4
                MenuBarIcon.compose(base: .dial, badge: v.1, awakeDot: v.2)
                    .draw(at: NSPoint(x: 8, y: y), from: .zero, operation: .sourceOver, fraction: 1)
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

        let model = AppModel()
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

        var tab = PanelView.Tab.timer
        if args.contains("--stats") {
            tab = .system
            model.stats.refresh() // primes the deltas
            usleep(600_000)
            model.stats.refresh()
        }
        if args.contains("--settings") {
            tab = .settings
        }
        if args.contains("--about") {
            tab = .about
        }

        // standalone windows: settings/about/converter
        let content: AnyView
        if args.contains("--window-settings") {
            content = AnyView(PanelView(initialTab: .settings, standaloneSettings: true).environmentObject(model))
        } else if args.contains("--window-about") {
            content = AnyView(PanelView(initialTab: .about, standaloneAbout: true).environmentObject(model))
        } else if args.contains("--window-converter") {
            content = AnyView(ConvertWindowView().environmentObject(model))
        } else {
            content = AnyView(PanelView(initialTab: tab).environmentObject(model))
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
}
