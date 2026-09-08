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
    /// The cursor and the typing field are AppKit views, and AppKit views come
    /// out as a yellow block when the canvas is rendered outside a running
    /// window. The self-test asks for the drawing alone.
    var chrome = true

    @State private var typing = false

    var body: some View {
        Canvas { context, size in
            for shape in surface.visible {
                draw(shape, canvas: size, in: &context)
            }
        }
        .background(alignment: .topLeading) {
            if let background {
                background.resizable().scaledToFit()
            }
        }
        .overlay(alignment: .topLeading) { held }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = MarkupPoint(x: value.location.x / scale, y: value.location.y / scale)
                    // `drafting` alone is not enough: the select tool holds its
                    // mark in `editing`, and the drag started the pick over on
                    // every step instead of moving anything.
                    if surface.isDragging {
                        surface.extend(to: point, modifiers: Self.heldKeys())
                    } else {
                        surface.begin(at: point)
                    }
                }
                .onEnded { _ in surface.finish() }
        )
        // AFTER the gesture: `contentShape` hands the whole area to the drag,
        // and a panel under it is a panel whose buttons never get the click —
        // pressing one deselected the mark and took the panel with it.
        .overlay(alignment: .topLeading) { if chrome { blurBar } }
        .overlay(alignment: .topLeading) { if chrome { typingField } }
        .overlay {
            if chrome {
                ToolCursor(tool: surface.tool,
                           width: surface.ink(for: surface.tool).width * scale)
                    .allowsHitTesting(false)
            }
        }
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

    /// What is in hand: a hairline round the mark, and a dot on every point it
    /// can be pulled by. A scribble has none — it moves whole.
    @ViewBuilder
    private var held: some View {
        if let shape = surface.selected {
            // A shape that already shows its own edge needs no box round it.
            let round = shape.tool == .magnifier || shape.tool == .oval || shape.tool == .blur
            let box = MarkupGeometry.boundingBox(shape.points)
            let frame = CGRect(x: box.origin.x * scale - 5, y: box.origin.y * scale - 5,
                               width: box.size.x * scale + 10, height: box.size.y * scale + 10)
            ZStack(alignment: .topLeading) {
                // A lens is its own outline; a box round it says nothing.
                if !round {
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.9),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: frame.width, height: frame.height)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .position(x: frame.midX, y: frame.midY)
                }

                // The dial belongs to the loupe alone; the others have nothing
                // to zoom.
                if shape.tool == .magnifier { dial(shape) }

                ForEach(Array(MarkupEditing.handles(of: shape).enumerated()), id: \.offset) { _, spot in
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .frame(width: 11, height: 11)
                        .position(x: spot.x * scale, y: spot.y * scale)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// What a blur does, under the blur itself: a mark is set where it is
    /// looked at. SPEC: docs/spec.md
    @ViewBuilder
    private var blurBar: some View {
        if let shape = surface.selected, shape.tool == .blur, let now = shape.blur {
            let box = MarkupGeometry.boundingBox(shape.points)
            HStack(spacing: 5) {
                chip("in", on: now.mode == .inside) { write { $0.mode = .inside } }
                chip("out", on: now.mode == .around) { write { $0.mode = .around } }
                divider
                chip("blur", on: now.style == .blur) { write { $0.style = .blur } }
                chip("dots", on: now.style == .pixels) { write { $0.style = .pixels } }
                divider
                chip("▢", on: now.shape == .rectangle) { write { $0.shape = .rectangle } }
                chip("◯", on: now.shape == .oval) { write { $0.shape = .oval } }
                divider
                Slider(value: Binding(
                    get: { Double(now.strength) },
                    set: { value in write { $0.strength = Int(value.rounded()) } }
                ), in: 1...10)
                .frame(width: 74)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Theme.isDark ? Color(white: 0.1) : Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Theme.controlStroke.opacity(0.6)))
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            )
            .fixedSize()
            .offset(x: (box.origin.x + box.size.x / 2) * scale - 160,
                    y: (box.origin.y + box.size.y) * scale + 12)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.divider).frame(width: 1, height: 16)
    }

    private func chip(_ title: String, on: Bool, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .font(Theme.mono(10))
                .foregroundStyle(on ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.chipBg : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func write(_ change: (inout MarkupBlur) -> Void) {
        var next = surface.blurInHand
        change(&next)
        surface.blurInHand = next
    }

    /// The arc a lens is zoomed by: a short track off its lower right with a
    /// knob on it. SPEC: docs/spec.md
    @ViewBuilder
    private func dial(_ shape: MarkupShape) -> some View {
        if let lens = MarkupEditing.lens(of: shape),
           let knob = MarkupEditing.Zoom.knob(of: shape) {
            let reach = (lens.radius + MarkupEditing.Zoom.gap) * scale
            let centre = CGPoint(x: lens.centre.x * scale, y: lens.centre.y * scale)
            let track = Path { path in
                path.addArc(center: centre, radius: reach,
                            startAngle: .degrees(MarkupEditing.Zoom.start),
                            endAngle: .degrees(MarkupEditing.Zoom.end), clockwise: false)
            }
            track.stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            track.stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Circle()
                .fill(Color.white)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 2)
                .frame(width: 11, height: 11)
                .position(x: knob.x * scale, y: knob.y * scale)
        }
    }

    @ViewBuilder
    private var typingField: some View {
        if let shape = surface.typing, let point = shape.points.first {
            SteadyField(text: Binding(
                get: { surface.typing?.text ?? "" },
                set: { surface.typing?.text = $0 }
            ), size: shape.ink.width * scale, weight: .semibold, monospaced: false,
               colour: Color(markupHex: shape.ink.hex),
               focus: $typing,
               onSubmit: { surface.commitTyping() })
            .frame(width: 240, height: shape.ink.width * scale + 10)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.fieldBg))
            .offset(x: point.x * scale, y: point.y * scale)
            // A field kept across two marks keeps the words of the first, and
            // the text looks as though it moved to wherever the second click
            // landed. One field per mark.
            .id(shape.id)
            .onAppear { typing = true }
        }
    }

    private func draw(_ shape: MarkupShape, canvas: CGSize, in context: inout GraphicsContext) {
        let colour = Color(markupHex: shape.ink.hex).opacity(surface.opacity(of: shape))
        let width = shape.ink.width * scale
        let stroke = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        let points = shape.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        guard let first = points.first else { return }

        switch shape.tool {
        case .select:
            return
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

        case .oval:
            guard points.count > 1 else { return }
            var path = Path()
            path.addEllipse(in: box(first, points[1]))
            context.stroke(path, with: .color(colour), style: stroke)

        case .magnifier:
            // Drawn HERE rather than baked into the backdrop, so the lens is
            // under the hand while it is being pulled out, not after.
            guard points.count > 1, let background else { return }
            let frame = round(box(first, points[1]))
            let lens = Path(ellipseIn: frame)
            context.drawLayer { layer in
                layer.clip(to: lens)
                // Twice the size about the lens's own centre, so what is under
                // the glass stays under it.
                let zoom = MarkupEditing.Zoom.of(shape)
                layer.draw(background, in: CGRect(x: frame.midX - frame.midX * zoom,
                                                  y: frame.midY - frame.midY * zoom,
                                                  width: canvas.width * zoom,
                                                  height: canvas.height * zoom))
            }
            glass(frame, rim: max(2, 4 * scale), in: &context)

        case .blur, .crop:
            guard points.count > 1 else { return }
            // The region says what it is by being blurred. A red dashed box
            // round it is a mark of its own, and it ends up in the file.
            let area = box(first, points[1])
            let outline: Path = shape.blur?.shape == .oval
                ? Path(ellipseIn: area) : Path(roundedRect: area, cornerRadius: 3)
            // No wash: the region is blurred for real while it is drawn, and a
            // white film over it would only lighten what is being hidden.
            context.stroke(outline, with: .color(.black.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 2))
            context.stroke(outline, with: .color(.white.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1))

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

    /// The rim of a lens: thick, colourless and lit from above, the way a
    /// glass one is. A coloured hairline reads as a drawn circle, not as glass.
    private func glass(_ frame: CGRect, rim: CGFloat, in context: inout GraphicsContext) {
        // Centred ON the circle, so the glass sits exactly in its rim and the
        // rim does not eat into what is under it.
        let edge = Path(ellipseIn: frame)
        context.stroke(edge, with: .color(.white.opacity(0.45)),
                       style: StrokeStyle(lineWidth: rim))
        // Brighter across the top left, dimmer across the bottom right: one
        // light, above and to the side.
        context.stroke(edge,
                       with: .linearGradient(
                        Gradient(colors: [.white.opacity(0.95), .white.opacity(0.1)]),
                        startPoint: CGPoint(x: frame.minX, y: frame.minY),
                        endPoint: CGPoint(x: frame.maxX, y: frame.maxY)),
                       style: StrokeStyle(lineWidth: rim * 0.55))
        context.stroke(Path(ellipseIn: frame.insetBy(dx: -rim / 2, dy: -rim / 2)),
                       with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 1))
        context.stroke(Path(ellipseIn: frame.insetBy(dx: rim / 2, dy: rim / 2)),
                       with: .color(.black.opacity(0.2)), style: StrokeStyle(lineWidth: 1))
    }

    /// The lens is a circle, whatever shape the drag was: the biggest one that
    /// fits, on the same centre.
    private func round(_ rect: CGRect) -> CGRect {
        let side = min(rect.width, rect.height)
        return CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
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
/// The pointer says which tool is in hand: a pencil for the freehand ones, a
/// crosshair for the ones that start at a point. An overlay that answers
/// SwiftUI's hit test swallows the drag under it, so this one answers none.
private struct ToolCursor: NSViewRepresentable {
    let tool: MarkupTool
    let width: Double

    func makeNSView(context: Context) -> NSView { CursorView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CursorView else { return }
        view.cursor = MarkupCursors.cursor(for: tool, width: width)
        view.window?.invalidateCursorRects(for: view)
    }

    final class CursorView: NSView {
        var cursor: NSCursor?
        private var area: NSTrackingArea?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let fresh = NSTrackingArea(rect: bounds,
                                       options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                       owner: self)
            addTrackingArea(fresh)
            area = fresh
        }

        override func cursorUpdate(with event: NSEvent) {
            if let cursor { cursor.set() } else { super.cursorUpdate(with: event) }
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            guard let cursor else { return }
            addCursorRect(bounds, cursor: cursor)
        }
    }
}
