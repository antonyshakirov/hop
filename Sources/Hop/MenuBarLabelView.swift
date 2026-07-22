import AppKit
import SwiftUI
import HopCore

/// Draws the status-bar star and its corner badges by hand. The composition
/// (which badges, where) is decided by the pure `IconBadges.compose`; this type
/// only renders `IconComposition` onto the fixed 22×17 canvas. Corner logic:
/// attention "!" top-left, awake dots top-right, time wedges bottom-right,
/// torrent arrows bottom-left. Colours are the documented exception to the
/// Theme-token rule — the star's badges use the fixed Apple system palette so
/// they read identically on every user's bar.
@MainActor
enum MenuBarIcon {
    enum Base {
        case dial
        case symbol(String)
    }

    // MARK: - Palette (fixed Apple system colours — the documented badge exception)

    /// Task-time wedge: an opaque dark green derived from systemGreen (~40%
    /// darker) but kept bright and saturated, so it reads as a second green next
    /// to the engine's systemGreen without going muddy. Mock-tuned value #159E46.
    static let darkGreen = NSColor(srgbRed: 0x15 / 255.0, green: 0x9E / 255.0, blue: 0x46 / 255.0, alpha: 1)
    /// Attention "!": a saturated deep red (mock #D81C0C) — darker and more
    /// urgent than plain systemRed, still legible on both light and dark bars.
    static let alertRed = NSColor(srgbRed: 0xD8 / 255.0, green: 0x1C / 255.0, blue: 0x0C / 255.0, alpha: 1)

    /// One unified stroke weight for every drawn glyph — the "!", the torrent
    /// arrows, the outline dot/wedge — so the whole badge set feels like one pen.
    private static let stroke: CGFloat = 0.95

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

    /// One canvas size for all states — badges occupy pre-reserved space, so the
    /// icon in the bar never "breathes". The star is always exactly centered.
    static let canvasSize = NSSize(width: 22, height: 17)

    /// Glyph centered: equal margins on the left and right.
    private static let dialRect = NSRect(x: 3.5, y: 1.5, width: 15, height: 14)

    /// Non-production build: TWO identical stars can live in the bar (production
    /// plus a dev or raw-debug instance) — indistinguishable without a mark. "D"
    /// in the bottom-left corner, monochrome.
    static var isDevBuild: Bool { Bundle.isDevBuild }

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

    /// The monochrome glyph colour matching the current menu-bar lightness.
    private static func glyphColor(dark: Bool) -> NSColor {
        dark ? .white : NSColor(white: 0, alpha: 0.85)
    }

    private static func currentlyDark() -> Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .aqua
    }

    /// Render the star (or the finish bell) plus every badge in `composition`.
    /// `dark` overrides the auto-detected bar lightness (used by snapshots);
    /// nil = read the live appearance.
    static func compose(_ composition: IconComposition, base: Base = .dial, dark: Bool? = nil) -> NSImage {
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        let dark = dark ?? currentlyDark()
        let glyph = glyphColor(dark: dark)

        switch base {
        case .dial:
            drawDial(color: glyph, in: dialRect)
        case .symbol(let name):
            draw(symbol: name, color: glyph, pointSize: 12.5,
                 at: NSRect(x: 4.5, y: 1, width: 16, height: 15), fraction: dark ? 1.0 : 0.85)
        }

        drawBadges(composition, glyph: glyph)

        // dev "D" — suppressed under a snapshot render (same rule as the Finder
        // dev-badge in AppIcon), so marketing/diagnostic shots show the real icon
        if isDevBuild && !Snapshot.active {
            drawDevMark(color: glyph.withAlphaComponent(dark ? 0.7 : 0.6))
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Badge layout

    /// All four corners, drawn onto the current focus. `colored` in the
    /// composition picks colour vs the mono fill/outline mapping.
    private static func drawBadges(_ c: IconComposition, glyph: NSColor) {
        let w = canvasSize.width, h = canvasSize.height

        // top-left: attention "!"
        if c.alert {
            drawBang(color: c.colored ? alertRed : glyph, atLeft: 1.4, top: h - 1.4)
        }

        // top-right: awake dots — yellow (no-sleep) then orange (lid), a dense
        // row with a light overlap; in 1x they melt into one two-colour blob.
        let dotD: CGFloat = 5.2
        let topY = h - dotD - 0.2
        let dots = c.badges.filter { $0.corner == .topRight }
        // right-anchored so a single dot sits in the far corner and a pair grows left
        var dotRight = w - 0.4
        // draw right-to-left so the first (no-sleep) ends up leftmost, overlapping under the lid
        for badge in dots.reversed() {
            let box = NSRect(x: dotRight - dotD, y: topY, width: dotD, height: dotD)
            drawDot(badge, box: box, colored: c.colored, glyph: glyph)
            dotRight -= dotD - 1.5 // 1.5pt overlap
        }

        // bottom-right: time wedges — green (engine) then dark-green (task). Sized
        // and placed to MIRROR the awake dots above (owner review): the SAME width,
        // the SAME right anchor and the SAME 1.5pt overlap as the dots, so each
        // wedge sits directly under its dot column — engine under no-sleep on the
        // left, task under lid on the right, the pair's width and centres matching
        // the dot pair's. Bigger and taller than the first cut, but the horizontal
        // footprint now equals the dots'. A thin dark keyline seam still keeps the
        // two greens reading as two.
        let wedges = c.badges.filter { $0.corner == .bottomRight }
        let wedgeW = dotD                 // == a dot's diameter → identical columns
        let wedgeH: CGFloat = 5.6         // taller than a dot; only the WIDTH must match
        let botY: CGFloat = 0.4
        // right-anchored column boxes, identical stride/overlap to the dots above
        var wedgeBoxes: [NSRect] = []
        var wedgeRight = w - 0.4
        for _ in wedges {
            wedgeBoxes.append(NSRect(x: wedgeRight - wedgeW, y: botY, width: wedgeW, height: wedgeH))
            wedgeRight -= dotD - 1.5       // 1.5pt overlap, same as the dots
        }
        // draw left→right so the RIGHT (task) wedge lands on top: its clean vertical
        // base is the seam boundary. wedges[0]=engine takes the LEFT column,
        // wedges.last=task the right (a lone wedge keeps the far-right column, like
        // a lone dot).
        for (badge, box) in zip(wedges, wedgeBoxes.reversed()) {
            drawWedge(badge, box: box, colored: c.colored, glyph: glyph)
        }
        // keyline seam laid on top, just left of the right wedge's base, so the
        // overlapping pair never fuses into one green blob
        if wedges.count > 1, let rightBox = wedgeBoxes.first {
            drawWedgeSeam(box: rightBox)
        }

        // bottom-left: torrent arrows — always the glyph colour (white on both
        // themes), the one bottom badge that is not green.
        if let torrent = c.torrent {
            drawTorrent(torrent, glyph: glyph)
        }
    }

    // MARK: - Glyphs

    /// Awake dot: a solid disc (no-sleep, and lid in colour) or a thin ring (lid
    /// in mono). Colour: systemYellow (no-sleep) / systemOrange (lid).
    private static func drawDot(_ badge: IconBadge, box: NSRect, colored: Bool, glyph: NSColor) {
        let color: NSColor = colored
            ? (badge == .noSleep ? .systemYellow : .systemOrange)
            : glyph
        let path = NSBezierPath(ovalIn: box)
        if colored || badge.monoFilled {
            color.setFill()
            path.fill()
        } else {
            // mono lid: a ring at the SAME outer size as the filled disc
            color.setStroke()
            let ring = NSBezierPath(ovalIn: box.insetBy(dx: stroke / 2, dy: stroke / 2))
            ring.lineWidth = stroke
            ring.stroke()
        }
    }

    /// A squat, seated, rounded play triangle — the branded PlayGlyph look
    /// (round-join bulge), flattened on the left and reduced in height per the
    /// spec. Filled (engine, and task in colour) or an outline of the SAME outer
    /// size (task in mono).
    private static func drawWedge(_ badge: IconBadge, box: NSRect, colored: Bool, glyph: NSColor) {
        let color: NSColor = colored
            ? (badge == .engineTime ? .systemGreen : darkGreen)
            : glyph
        // rounding via a thick round-join stroke, exactly like PlayGlyph
        let round = box.width * 0.42
        let filled = colored || badge.monoFilled
        // The filled wedge is a triangle inset by round/2 and grown back OUT by a
        // round-join stroke of width `round`, so its outer edge lands on `box`. The
        // mono outline must reach that SAME outer edge (only hollow inside), so its
        // triangle is inset by just stroke/2 and grown back by a `stroke`-wide round
        // join — both then share identical outer bounds; only the wall differs (full
        // fill vs a thin ring). Insetting by round/2 too, as before, left the outline
        // (round-stroke)/2 short on every side and it read visibly smaller.
        let inset = filled ? round / 2 : stroke / 2
        // seated base: the left edge is shorter than the full height (not
        // equilateral); the apex sits on the vertical centre. Trimmed from 0.35
        // so the wedge keeps more height (owner review: it read too pancaked).
        let baseInset: CGFloat = 0.12
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: box.minX + inset, y: box.minY + inset + baseInset))
        tri.line(to: NSPoint(x: box.minX + inset, y: box.maxY - inset - baseInset))
        tri.line(to: NSPoint(x: box.maxX - inset, y: box.midY))
        tri.close()
        tri.lineJoinStyle = .round
        color.setStroke()
        tri.lineWidth = filled ? round : stroke
        if filled {
            color.setFill()
            tri.fill()
        }
        tri.stroke()
    }

    /// The thin dark keyline drawn just left of a wedge that has a neighbour, so
    /// an adjacent pair reads as two marks even at 1x where they nearly touch.
    private static func drawWedgeSeam(box: NSRect) {
        NSColor.black.withAlphaComponent(0.9).setStroke()
        let seam = NSBezierPath()
        // sits in the middle of the tighter gap now that the pair is closer
        seam.move(to: NSPoint(x: box.minX - 0.25, y: box.minY))
        seam.line(to: NSPoint(x: box.minX - 0.25, y: box.maxY))
        seam.lineWidth = stroke
        seam.lineCapStyle = .round
        seam.stroke()
    }

    /// Attention "!": a rounded stem plus a dot below it, anchored at its top-left.
    private static func drawBang(color: NSColor, atLeft x: CGFloat, top: CGFloat) {
        color.setFill()
        let stemW = stroke * 1.15
        let stemH: CGFloat = 3.2
        let stem = NSRect(x: x, y: top - stemH, width: stemW, height: stemH)
        NSBezierPath(roundedRect: stem, xRadius: stemW / 2, yRadius: stemW / 2).fill()
        let dotD = stemW
        NSBezierPath(ovalIn: NSRect(
            x: x, y: top - stemH - dotD - 0.9, width: dotD, height: dotD
        )).fill()
    }

    /// Torrent arrows in the bottom-left: ↓ downloading, ↑ seeding, both side by
    /// side when both are happening. Unified thin stroke, the star's glyph colour.
    private static func drawTorrent(_ dir: TorrentArrows, glyph: NSColor) {
        switch dir {
        case .down: drawArrow(down: true, cx: 3.0, glyph: glyph, full: true)
        case .up: drawArrow(down: false, cx: 3.0, glyph: glyph, full: true)
        case .both:
            drawArrow(down: true, cx: 2.2, glyph: glyph, full: false)
            drawArrow(down: false, cx: 5.0, glyph: glyph, full: false)
        }
    }

    private static func drawArrow(down: Bool, cx: CGFloat, glyph: NSColor, full: Bool) {
        glyph.setStroke()
        let bottom: CGFloat = 0.9
        let height: CGFloat = full ? 5.2 : 4.6
        let top = bottom + height
        let head: CGFloat = full ? 1.7 : 1.4
        let shaft = NSBezierPath()
        shaft.move(to: NSPoint(x: cx, y: bottom))
        shaft.line(to: NSPoint(x: cx, y: top))
        shaft.lineWidth = stroke
        shaft.lineCapStyle = .round
        shaft.lineJoinStyle = .round
        shaft.stroke()
        // chevron head at the pointing end
        let tipY = down ? bottom : top
        let backY = down ? bottom + head : top - head
        let chev = NSBezierPath()
        chev.move(to: NSPoint(x: cx - head * 0.75, y: backY))
        chev.line(to: NSPoint(x: cx, y: tipY))
        chev.line(to: NSPoint(x: cx + head * 0.75, y: backY))
        chev.lineWidth = stroke
        chev.lineCapStyle = .round
        chev.lineJoinStyle = .round
        chev.stroke()
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
