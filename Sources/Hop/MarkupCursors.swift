import AppKit
import HopCore
import SwiftUI

/// The pointer for each tool, drawn from the same glyphs the toolbar uses so a
/// pencil in hand looks like the pencil that was pressed. macOS ships no pencil
/// cursor, and an arrow says nothing about what a click is about to do.
@MainActor
enum MarkupCursors {
    private static var made: [MarkupGlyph: NSCursor] = [:]
    private static var nibs: [String: NSCursor] = [:]

    static func cursor(for tool: MarkupTool, width: Double) -> NSCursor? {
        switch tool {
        case .pencil, .fadingInk:
            return nib(width: width, round: true)
        case .marker:
            return nib(width: width, round: false, squat: true)
        case .eraser:
            return drawn(MarkupToolbar.glyph(for: tool))
        case .select:
            return .arrow
        case .blur:
            // A plain crosshair says "draw something" and no more. The badge
            // says WHICH something is about to be drawn.
            return aiming(with: .blur)
        case .text:
            return .iBeam
        default:
            return .crosshair
        }
    }

    /// The nib itself: the shape and the size of the mark about to be made, so
    /// its weight is known before a line of it is drawn. Round for the pens,
    /// square for the chisel of a marker.
    private static func nib(width: Double, round: Bool, squat: Bool = false) -> NSCursor? {
        let thickness = min(max(width, 3), 48)
        let key = "\(round ? "round" : "flat")-\(squat)-\(Int(thickness.rounded()))"
        if let ready = nibs[key] { return ready }

        // A chisel is narrow and tall, upright: the end of the nib, seen
        // straight on.
        let broad = squat ? max(3, CGFloat(thickness) / 3) : CGFloat(thickness)
        let long = CGFloat(thickness)
        let side = (max(broad, long) + 8).rounded()
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let box = CGRect(x: (side - broad) / 2, y: (side - long) / 2,
                             width: broad, height: long)
            let path = round
                ? CGPath(ellipseIn: box, transform: nil)
                : CGPath(roundedRect: box, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            context.setLineWidth(2.4)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.65).cgColor)
            context.addPath(path)
            context.strokePath()
            context.setLineWidth(1)
            context.setStrokeColor(NSColor.white.cgColor)
            context.addPath(path)
            context.strokePath()
            return true
        }

        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
        nibs[key] = cursor
        return cursor
    }

    /// A crosshair with the tool's own glyph beside it, so a region drawn for
    /// one purpose is not mistaken for a region drawn for another.
    private static func aiming(with glyph: MarkupGlyph) -> NSCursor? {
        if let ready = made[glyph] { return ready }

        let side: CGFloat = 30
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            var cross = Path()
            cross.move(to: CGPoint(x: 1, y: 13)); cross.addLine(to: CGPoint(x: 9, y: 13))
            cross.move(to: CGPoint(x: 17, y: 13)); cross.addLine(to: CGPoint(x: 25, y: 13))
            cross.move(to: CGPoint(x: 13, y: 1)); cross.addLine(to: CGPoint(x: 13, y: 9))
            cross.move(to: CGPoint(x: 13, y: 17)); cross.addLine(to: CGPoint(x: 13, y: 25))
            paint(cross.strokedPath(StrokeStyle(lineWidth: 1.2, lineCap: .round)).cgPath,
                  in: context)

            var badge = Path()
            let shrink = CGAffineTransform(scaleX: 0.55, y: 0.55)
                .concatenating(CGAffineTransform(translationX: 15, y: 15))
            for stroke in MarkupIcons.strokes(for: glyph) {
                let path = stroke.filled
                    ? stroke.path
                    : stroke.path.strokedPath(
                        StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
                badge.addPath(path.applying(shrink))
            }
            paint(badge.cgPath, in: context)
            return true
        }

        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: 13, y: 13))
        made[glyph] = cursor
        return cursor
    }

    private static func paint(_ path: CGPath, in context: CGContext) {
        context.setLineJoin(.round)
        context.setLineWidth(2.4)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        context.addPath(path)
        context.strokePath()
        context.setFillColor(NSColor.white.cgColor)
        context.addPath(path)
        context.fillPath()
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
