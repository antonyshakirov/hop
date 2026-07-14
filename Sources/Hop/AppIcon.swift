import AppKit

/// App icon in Finder/Applications: dark or light, light by default
/// (Anton, 2026-07-15 — the light one is more noticeable; "auto" removed,
/// the toggle is a small delight, not a theme).
/// Applied via NSWorkspace.setIcon; in the menu bar the icon always
/// stays a monochrome system template.
@MainActor
enum AppIcon {
    static let styleKey = "appIconStyle" // dark | light (legacy "auto" → light)

    static var isDark: Bool {
        UserDefaults.standard.string(forKey: styleKey) == "dark"
    }

    static func apply() {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { return } // dev run without a bundle
        let ok = NSWorkspace.shared.setIcon(image(dark: isDark), forFile: path, options: [])
        if !ok {
            // a half-written custom icon leaves the Finder flag without a
            // resource and the app renders as a FOLDER; roll the flag back
            NSWorkspace.shared.setIcon(nil, forFile: path, options: [])
        }
    }

    /// Small previews for the settings chips — the real icons, not words.
    static func preview(dark: Bool) -> NSImage {
        let img = image(dark: dark)
        img.size = NSSize(width: 30, height: 30)
        return img
    }

    /// Drawn via drawingHandler: redrawn at the target resolution,
    /// no blur on Retina.
    private static func image(dark: Bool) -> NSImage {
        NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
            let inset = rect.insetBy(dx: 50, dy: 50)
            let background = NSBezierPath(roundedRect: inset, xRadius: 94, yRadius: 94)
            let bg = dark
                ? NSColor(white: 0.045, alpha: 1)
                : NSColor(red: 0.973, green: 0.968, blue: 0.955, alpha: 1)
            bg.setFill()
            background.fill()
            MenuBarIcon.drawDial(
                color: dark ? .white : NSColor(white: 0.05, alpha: 1),
                in: inset.insetBy(dx: 86, dy: 86)
            )
            // dev build (bundle id …minimo.dev): a "D" badge in the corner,
            // so production and test versions are told apart at a glance
            if Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true {
                let badge = NSRect(x: rect.maxX - 190, y: rect.minY + 60, width: 130, height: 130)
                let plate = NSBezierPath(roundedRect: badge, xRadius: 32, yRadius: 32)
                NSColor(red: 0.79, green: 0.62, blue: 0.23, alpha: 1).setFill() // dark gold
                plate.fill()
                let letter = "D" as NSString
                let font = NSFont.monospacedSystemFont(ofSize: 92, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: NSColor(white: 0.05, alpha: 1),
                ]
                let size = letter.size(withAttributes: attrs)
                letter.draw(
                    at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2),
                    withAttributes: attrs
                )
            }
            return true
        }
    }
}
