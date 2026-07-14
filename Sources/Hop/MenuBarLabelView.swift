import AppKit
import SwiftUI

/// Draws the status-bar icon by hand when color is needed:
/// yellow awake dot (top corner) and timer status (bottom corner) —
/// green ▶ = running, orange ⏸ = paused.
@MainActor
enum MenuBarIcon {
    enum StateBadge {
        case running, paused

        var symbol: String { self == .running ? "play.fill" : "pause.fill" }
        var color: NSColor { self == .running ? .systemGreen : .systemOrange }
    }

    enum Base {
        case dial
        case symbol(String)
    }

    /// Signature glyph: an asterisk star with round caps.
    static func drawDial(color: NSColor, in rect: NSRect) {
        color.setStroke()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.38
        let path = NSBezierPath()
        for i in 0..<8 {
            // 8 rays rotated by half a step — no strict vertical
            let angle = CGFloat(i) * .pi / 4 + .pi / 8
            path.move(to: center)
            path.line(to: NSPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            ))
        }
        path.lineWidth = rect.width * 0.095
        path.lineCapStyle = .round
        path.stroke()
    }

    /// One canvas size for all states — badges occupy pre-reserved
    /// space, so the icon in the bar never "breathes".
    /// The left ("!") and right (badges/dot) zones are EQUAL at 3.5pt — margins
    /// were tightened at Anton's request, but the dots and the mark still fit;
    /// the star is always exactly centered on the canvas.
    static let canvasSize = NSSize(width: 22, height: 17)

    /// Glyph centered: equal margins on the left and right.
    private static let dialRect = NSRect(x: 3.5, y: 1.5, width: 15, height: 14)

    /// Dev build: TWO identical stars live in the bar (production and dev) —
    /// indistinguishable without a mark. "D" in the bottom-left corner, monochrome.
    static var isDevBuild: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    }

    private static func drawDevMark(color: NSColor) {
        let r = NSRect(x: 0.9, y: 0.9, width: 3.4, height: 5.6)
        let path = NSBezierPath()
        path.lineWidth = 1.1
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: r.minX, y: r.minY))
        path.line(to: NSPoint(x: r.minX, y: r.maxY))
        path.curve(to: NSPoint(x: r.minX, y: r.minY),
                   controlPoint1: NSPoint(x: r.maxX + 1.6, y: r.maxY),
                   controlPoint2: NSPoint(x: r.maxX + 1.6, y: r.minY))
        color.setStroke()
        path.stroke()
    }

    /// Template version for the calm state — macOS tints it to match the bar.
    static let dialTemplate: NSImage = {
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        drawDial(color: .black, in: dialRect)
        if isDevBuild { drawDevMark(color: .black) }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }()

    /// awakeDot: yellow — no-sleep is active; orange — ONLY the lid is
    /// enabled (can be closed, but without no-sleep the Mac will doze off); nil — no dot.
    static func compose(base: Base, badge: StateBadge?, awakeDot: NSColor?, alertMark: Bool = false) -> NSImage {
        let size = canvasSize
        let image = NSImage(size: size)
        image.lockFocus()

        // monochrome glyph matching the current menu bar lightness
        let dark = NSApplication.shared.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) != .aqua
        let glyphColor: NSColor = dark ? .white : .black

        switch base {
        case .dial:
            drawDial(
                color: dark ? glyphColor : glyphColor.withAlphaComponent(0.85),
                in: dialRect
            )
        case .symbol(let name):
            draw(symbol: name, color: glyphColor, pointSize: 12.5,
                 at: NSRect(x: 4.5, y: 1, width: 16, height: 15),
                 fraction: dark ? 1.0 : 0.85)
        }

        if let badge {
            drawBadge(badge, in: NSRect(x: size.width - 8, y: 0.5, width: 7, height: 7))
        }
        if let awakeDot {
            awakeDot.setFill()
            NSBezierPath(ovalIn: NSRect(
                x: size.width - 6.5, y: size.height - 6.5, width: 6, height: 6
            )).fill()
        }
        if isDevBuild {
            drawDevMark(color: glyphColor.withAlphaComponent(0.7))
        }
        if alertMark {
            // monitor red zone: a neat "!" at the top left —
            // deliberately a mark, not a third dot (the right side already has two)
            NSColor.systemRed.setFill()
            NSBezierPath(roundedRect: NSRect(
                x: 1.1, y: size.height - 5.4, width: 1.8, height: 4.4
            ), xRadius: 0.9, yRadius: 0.9).fill()
            NSBezierPath(ovalIn: NSRect(
                x: 1.1, y: size.height - 8.4, width: 1.8, height: 1.8
            )).fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// Badges are drawn with our own rounded-corner paths — SF Symbols
    /// look spiky at this size.
    private static func drawBadge(_ badge: StateBadge, in rect: NSRect) {
        badge.color.setFill()
        badge.color.setStroke()
        switch badge {
        case .running:
            // triangle ▶ rounded via a thick round-join stroke
            let inset = rect.insetBy(dx: 1.2, dy: 1.2)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: inset.minX, y: inset.minY))
            path.line(to: NSPoint(x: inset.minX, y: inset.maxY))
            path.line(to: NSPoint(x: inset.maxX, y: inset.midY))
            path.close()
            path.lineJoinStyle = .round
            path.lineWidth = 2.4
            path.fill()
            path.stroke()
        case .paused:
            // two bars ⏸ with rounded caps
            let barWidth: CGFloat = 2.2
            for x in [rect.minX + 0.6, rect.maxX - barWidth - 0.6] {
                NSBezierPath(
                    roundedRect: NSRect(x: x, y: rect.minY, width: barWidth, height: rect.height),
                    xRadius: barWidth / 2, yRadius: barWidth / 2
                ).fill()
            }
        }
    }

    private static func draw(
        symbol: String, color: NSColor, pointSize: CGFloat, at rect: NSRect, fraction: CGFloat
    ) {
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
        else { return }
        let tinted = NSImage(size: base.size)
        tinted.lockFocus()
        base.draw(
            in: NSRect(origin: .zero, size: base.size),
            from: .zero, operation: .sourceOver, fraction: 1.0
        )
        color.set()
        NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
        tinted.unlockFocus()

        // fit while preserving aspect ratio
        let scale = min(rect.width / base.size.width, rect.height / base.size.height, 1)
        let drawSize = NSSize(width: base.size.width * scale, height: base.size.height * scale)
        let origin = NSPoint(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2
        )
        tinted.draw(
            in: NSRect(origin: origin, size: drawSize),
            from: .zero, operation: .sourceOver, fraction: fraction
        )
    }
}
