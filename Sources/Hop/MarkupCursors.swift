import AppKit
import HopCore
import SwiftUI

/// The pointer for each tool, drawn from the same glyphs the toolbar uses so a
/// pencil in hand looks like the pencil that was pressed. macOS ships no pencil
/// cursor, and an arrow says nothing about what a click is about to do.
@MainActor
enum MarkupCursors {
    private static var made: [MarkupGlyph: NSCursor] = [:]

    static func cursor(for tool: MarkupTool, width: Double) -> NSCursor? {
        switch tool {
        case .pencil, .fadingInk, .marker, .eraser:
            return drawn(MarkupToolbar.glyph(for: tool))
        case .select:
            return .arrow
        case .text:
            return .iBeam
        default:
            return .crosshair
        }
    }

    /// The glyph in white over a black outline, so it holds on any picture.
    /// The hot spot is the drawing tip: the family is built upright and turned
    /// by 45°, which puts every tip at the lower left.
    private static func drawn(_ glyph: MarkupGlyph) -> NSCursor? {
        if let ready = made[glyph] { return ready }

        let side: CGFloat = 24
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            var silhouette = Path()
            for stroke in MarkupIcons.strokes(for: glyph) {
                if stroke.filled {
                    silhouette.addPath(stroke.path)
                } else {
                    silhouette.addPath(stroke.path.strokedPath(
                        StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)))
                }
            }
            let path = silhouette.cgPath

            context.setLineJoin(.round)
            context.setLineWidth(2.6)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.75).cgColor)
            context.addPath(path)
            context.strokePath()

            context.setFillColor(NSColor.white.cgColor)
            context.addPath(path)
            context.fillPath()
            return true
        }

        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 16))
        made[glyph] = cursor
        return cursor
    }
}
