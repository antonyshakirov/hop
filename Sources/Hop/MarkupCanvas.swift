import AppKit
import HopCore
import SwiftUI

/// Draws a surface's marks and turns dragging into new ones.
///
/// The background is whatever lies under the marks: a captured frame in the
/// editor, nothing at all over the live screen.
struct MarkupCanvas: View {
    @ObservedObject var surface: MarkupSurface
    var background: Image?
    var scale: CGFloat = 1

    @State private var pointer: CGPoint?

    var body: some View {
        Canvas { context, _ in
            for shape in surface.visible {
                draw(shape, in: &context)
            }
        }
        .background(alignment: .topLeading) {
            if let background {
                background.resizable().scaledToFit()
            }
        }
        .overlay(alignment: .topLeading) { aim }
        .overlay(alignment: .topLeading) { typingField }
        .overlay {
            CrosshairArea(active: MarkupCanvas.aims(surface.tool),
                          onMove: { pointer = $0 },
                          onLeave: { pointer = nil })
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = MarkupPoint(x: value.location.x / scale, y: value.location.y / scale)
                    if surface.drafting == nil {
                        surface.begin(at: point)
                    } else {
                        surface.extend(to: point, modifiers: Self.heldKeys())
                    }
                }
                .onEnded { _ in surface.finish() }
        )
    }

    /// A drag reads the modifier keys as they are RIGHT NOW: SwiftUI's gesture
    /// value carries the place of the pointer and nothing about the keyboard.
    private static func heldKeys() -> MarkupDrag.Modifiers {
        let flags = NSEvent.modifierFlags
        return MarkupDrag.Modifiers(fromCentre: flags.contains(.option),
                                    regular: flags.contains(.shift))
    }

    /// Tools that begin at a point rather than follow the hand.
    static func aims(_ tool: MarkupTool) -> Bool {
        switch tool {
        case .pencil, .fadingInk, .marker, .eraser, .text: return false
        default: return true
        }
    }

    /// Before the drag, guides across the whole picture through the pointer;
    /// during it, the spot the shape is growing out of. Either way the point a
    /// shape starts from is never a guess.
    @ViewBuilder
    private var aim: some View {
        if let anchor = surface.anchor {
            cross(at: CGPoint(x: anchor.x * scale, y: anchor.y * scale), reach: 9)
        } else if MarkupCanvas.aims(surface.tool), let pointer {
            guides(at: pointer)
        }
    }

    /// A dark line under the white one: on a white page a white hairline is not
    /// there at all.
    private func cross(at spot: CGPoint, reach: CGFloat) -> some View {
        let path = Path { path in
            path.move(to: CGPoint(x: spot.x - reach, y: spot.y))
            path.addLine(to: CGPoint(x: spot.x + reach, y: spot.y))
            path.move(to: CGPoint(x: spot.x, y: spot.y - reach))
            path.addLine(to: CGPoint(x: spot.x, y: spot.y + reach))
        }
        return ZStack {
            path.stroke(Color.black.opacity(0.55), lineWidth: 3.5)
            path.stroke(Color.white, lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }

    private func guides(at point: CGPoint) -> some View {
        let lines = Path { path in
            path.move(to: CGPoint(x: 0, y: point.y))
            path.addLine(to: CGPoint(x: 100_000, y: point.y))
            path.move(to: CGPoint(x: point.x, y: 0))
            path.addLine(to: CGPoint(x: point.x, y: 100_000))
        }
        return ZStack {
            lines.stroke(Color.black.opacity(0.35), lineWidth: 3)
            lines.stroke(Color.white.opacity(0.75), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var typingField: some View {
        if let shape = surface.typing, let point = shape.points.first {
            TextField("", text: Binding(
                get: { surface.typing?.text ?? "" },
                set: { surface.typing?.text = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: shape.ink.width * scale, weight: .semibold))
            .foregroundStyle(Color(markupHex: shape.ink.hex))
            .frame(width: 240)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.fieldBg))
            .offset(x: point.x * scale, y: point.y * scale)
            .onSubmit { surface.commitTyping() }
        }
    }

    private func draw(_ shape: MarkupShape, in context: inout GraphicsContext) {
        let colour = Color(markupHex: shape.ink.hex).opacity(surface.opacity(of: shape))
        let width = shape.ink.width * scale
        let stroke = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        let points = shape.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        guard let first = points.first else { return }

        switch shape.tool {
        case .pencil, .fadingInk:
            context.stroke(freehand(points), with: .color(colour), style: stroke)

        case .marker:
            context.drawLayer { layer in
                layer.blendMode = .multiply
                layer.stroke(freehand(points), with: .color(colour.opacity(0.45)), style: stroke)
            }

        case .line:
            guard points.count > 1 else { return }
            context.stroke(segment(first, points[1]), with: .color(colour), style: stroke)

        case .arrow:
            guard points.count > 1 else { return }
            drawArrow(from: shape.points[0], to: shape.points[1], shape: shape,
                      colour: colour, stroke: stroke, in: &context)

        case .rectangle:
            guard points.count > 1 else { return }
            context.stroke(Path(roundedRect: box(first, points[1]), cornerRadius: 4 * scale),
                           with: .color(colour), style: stroke)

        case .oval, .magnifier:
            guard points.count > 1 else { return }
            var path = Path()
            path.addEllipse(in: box(first, points[1]))
            context.stroke(path, with: .color(colour), style: stroke)

        case .blur, .crop:
            guard points.count > 1 else { return }
            context.stroke(Path(box(first, points[1])), with: .color(colour),
                           style: StrokeStyle(lineWidth: max(1.5, width / 2), dash: [6, 4]))

        case .steps:
            let radius = 17 * scale
            let circle = CGRect(x: first.x - radius, y: first.y - radius,
                                width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: circle), with: .color(colour))
            let number = Text("\(shape.step ?? 1)")
                .font(.system(size: 19 * scale, weight: .bold))
                .foregroundStyle(Color.white)
            context.draw(number, at: first)

        case .text:
            let label = Text(shape.text ?? "")
                .font(.system(size: shape.ink.width * scale, weight: .semibold))
                .foregroundStyle(colour)
            context.draw(label, at: first, anchor: .topLeading)

        case .eraser:
            return
        }
    }

    private func drawArrow(
        from: MarkupPoint, to: MarkupPoint, shape: MarkupShape,
        colour: Color, stroke: StrokeStyle, in context: inout GraphicsContext
    ) {
        let tail = CGPoint(x: from.x * scale, y: from.y * scale)
        let tip = CGPoint(x: to.x * scale, y: to.y * scale)

        let style = shape.arrow ?? .solid
        let head = MarkupGeometry.arrowHead(from: from, to: to, style: style, width: shape.ink.width)
        let barbs = head.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }

        // The shaft stops where the head begins. Run to the tip and its round
        // cap sticks out past the point, and the LINE becomes the tip.
        let stop = barbs.count == 3 ? barbs[1] : shortened(tail, tip, by: shape.ink.width * scale / 2)
        context.stroke(segment(tail, stop), with: .color(colour), style: stroke)

        if barbs.count == 3 {
            var triangle = Path()
            triangle.move(to: barbs[0])
            triangle.addLine(to: tip)
            triangle.addLine(to: barbs[2])
            triangle.addLine(to: barbs[1])
            triangle.closeSubpath()
            context.fill(triangle, with: .color(colour))
        } else if barbs.count == 2 {
            // Two open barbs rather than a filled head: they are drawn with the
            // shaft's own stroke, so the tip keeps one thickness.
            var open = Path()
            for barb in barbs {
                open.move(to: barb)
                open.addLine(to: tip)
            }
            context.stroke(open, with: .color(colour), style: stroke)
        }
    }

    private func shortened(_ from: CGPoint, _ to: CGPoint, by amount: CGFloat) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > amount else { return to }
        return CGPoint(x: to.x - dx / length * amount, y: to.y - dy / length * amount)
    }

    private func freehand(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func segment(_ a: CGPoint, _ b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    private func box(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}


/// A crosshair over the picture while a tool that starts at a point is in hand.
private struct CrosshairArea: NSViewRepresentable {
    let active: Bool
    let onMove: (CGPoint) -> Void
    let onLeave: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = AimView()
        view.active = active
        view.onMove = onMove
        view.onLeave = onLeave
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? AimView else { return }
        view.active = active
        view.onMove = onMove
        view.onLeave = onLeave
        view.window?.invalidateCursorRects(for: view)
    }

    /// SwiftUI reports a moving mouse only once a button is down, and the
    /// guides have to be there before that.
    final class AimView: NSView {
        var active = false
        var onMove: ((CGPoint) -> Void)?
        var onLeave: (() -> Void)?
        private var area: NSTrackingArea?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let fresh = NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
            addTrackingArea(fresh)
            area = fresh
        }

        override func mouseMoved(with event: NSEvent) {
            guard active else { return }
            onMove?(convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            onLeave?()
        }

        override func cursorUpdate(with event: NSEvent) {
            if active { NSCursor.crosshair.set() } else { super.cursorUpdate(with: event) }
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            guard active else { return }
            addCursorRect(bounds, cursor: .crosshair)
        }
    }
}
