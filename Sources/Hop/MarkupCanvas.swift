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
    /// Whether `background` already carries the blur baked into it.
    var baked = false
    /// The pixels the loupe and the blur read when there is no background to
    /// read them from: the live screen under the drawing layer.
    var source: Image?
    var mosaics: [Int: Image] = [:]
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
                           width: surface.ink(for: surface.tool).width * scale,
                           active: !surface.pointerOverPanel)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The words as they will be drawn, and the height of one line of them.
    static func span(of shape: MarkupShape, scale: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: shape.ink.width * scale, weight: .semibold)
        let line = lineHeight(shape.ink.width * scale)
        let words = shape.text ?? ""
        guard !words.isEmpty else { return CGSize(width: 40, height: line) }
        return CGSize(width: ceil((words as NSString).size(withAttributes: [.font: font]).width),
                      height: line)
    }

    static func lineHeight(_ size: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        return ceil(font.ascender - font.descender + font.leading)
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

    /// What is in hand: a dot on every point the mark can be pulled by, and a
    /// hairline round it only when it has no such points to show.
    @ViewBuilder
    private var held: some View {
        if let shape = surface.selected {
            let box = MarkupGeometry.boundingBox(shape.points)
            // A caption is stored as ONE point; its box is the words themselves.
            let span = shape.tool == .text
                ? Self.span(of: shape, scale: scale)
                : CGSize(width: box.size.x * scale, height: box.size.y * scale)
            let frame = CGRect(x: box.origin.x * scale - 5, y: box.origin.y * scale - 5,
                               width: span.width + 10, height: span.height + 10)
            ZStack(alignment: .topLeading) {
                if MarkupEditing.boxed(shape) {
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
                if now.offersDim {
                    divider
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                    Slider(value: Binding(
                        get: { Double(now.dim) },
                        set: { value in write { $0.dim = Int(value.rounded()) } }
                    ), in: 0...10)
                    .frame(width: 74)
                }
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
            .onHover { surface.pointerOverPanel = $0 }
            .fixedSize()
            .offset(x: (box.origin.x + box.size.x / 2) * scale - (now.offersDim ? 210 : 160),
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
            .frame(width: 240, height: Self.lineHeight(shape.ink.width * scale))
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.fieldBg))
            // The caret has to stand where the caption will be drawn, or the
            // words jump the moment they are committed. A text field insets its
            // own text by two points; the canvas draws from the point itself.
            .offset(x: point.x * scale - 2, y: point.y * scale)
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
            // ONE area, filled once: translucent ink stroked over itself lays a
            // second, darker line down the middle of the stroke. The nib is
            // SQUARE and the same in every direction — a chisel that thinned
            // out along its own axis lost the middle of a horizontal stroke
            // (Anton, 2026-09-09). SPEC: docs/spec.md — the marker.
            let swept = freehand(points).strokedPath(
                StrokeStyle(lineWidth: max(width, 1), lineCap: .square, lineJoin: .round))
            context.drawLayer { layer in
                layer.blendMode = .multiply
                layer.fill(swept, with: .color(colour.opacity(0.45)))
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
            guard points.count > 1 else { return }
            let frame = round(box(first, points[1]))
            let lens = Path(ellipseIn: frame)
            // SPEC: docs/spec.md — a loupe with nothing to read fails closed.
            guard let under = background ?? source else {
                context.fill(lens, with: .color(.black))
                glass(frame, rim: max(2, 4 * scale), in: &context)
                return
            }
            let zoom = MarkupEditing.Zoom.of(shape)
            let eye = CGPoint(x: frame.midX, y: frame.midY)
            context.drawLayer { layer in
                layer.clip(to: lens)
                // Twice the size about the lens's own centre, so what is under
                // the glass stays under it.
                layer.draw(under, in: CGRect(x: eye.x - eye.x * zoom, y: eye.y - eye.y * zoom,
                                             width: canvas.width * zoom,
                                             height: canvas.height * zoom))
                // SPEC: docs/spec.md — the loupe magnifies what the blur left.
                if !baked {
                    for hidden in surface.visible where hidden.tool == .blur {
                        smear(hidden, canvas: canvas, zoom: zoom, about: eye, in: &layer)
                    }
                }
                // SPEC: docs/spec.md — the loupe magnifies the marks laid before it.
                layer.translateBy(x: eye.x, y: eye.y)
                layer.scaleBy(x: zoom, y: zoom)
                layer.translateBy(x: -eye.x, y: -eye.y)
                for mark in MarkupEditing.beneath(shape, in: surface.visible) {
                    draw(mark, canvas: canvas, in: &layer)
                }
            }
            glass(frame, rim: max(2, 4 * scale), in: &context)

        case .blur, .crop:
            guard points.count > 1 else { return }
            let area = box(first, points[1])
            // Over the live screen nothing under the mark is baked into a
            // backdrop, so the blur is drawn here, from the streamed frame.
            if shape.tool == .blur, !baked {
                smear(shape, canvas: canvas, zoom: 1,
                      about: CGPoint(x: area.midX, y: area.midY), in: &context)
            }
            // The region says what it is by being blurred. A red dashed box
            // round it is a mark of its own, and it ends up in the file.
            // No wash: the region is blurred for real while it is drawn, and a
            // white film over it would only lighten what is being hidden.
            let ring = outline(of: shape, in: area)
            context.stroke(ring, with: .color(.black.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 2))
            context.stroke(ring, with: .color(.white.opacity(0.8)),
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

    private func outline(of shape: MarkupShape, in area: CGRect) -> Path {
        shape.blur?.shape == .oval ? Path(ellipseIn: area) : Path(roundedRect: area, cornerRadius: 3)
    }

    private func plate(_ shape: MarkupShape, area: CGRect, canvas: CGSize) -> (Path, FillStyle) {
        let out = shape.blur?.mode == .around
        var path = outline(of: shape, in: area)
        guard out else { return (path, FillStyle()) }
        var inverted = Path(CGRect(origin: .zero, size: canvas))
        inverted.addPath(path)
        path = inverted
        return (path, FillStyle(eoFill: true))
    }

    /// SPEC: docs/spec.md — the blur over the live screen.
    private func smear(_ shape: MarkupShape, canvas: CGSize, zoom: CGFloat, about eye: CGPoint,
                       in context: inout GraphicsContext) {
        guard shape.points.count > 1 else { return }
        func zoomed(_ rect: CGRect) -> CGRect {
            CGRect(x: eye.x + (rect.minX - eye.x) * zoom, y: eye.y + (rect.minY - eye.y) * zoom,
                   width: rect.width * zoom, height: rect.height * zoom)
        }
        let area = box(CGPoint(x: shape.points[0].x * scale, y: shape.points[0].y * scale),
                       CGPoint(x: shape.points[1].x * scale, y: shape.points[1].y * scale))
        let whole = CGRect(origin: .zero, size: canvas)
        let (bitten, style) = plate(shape, area: zoomed(area), canvas: canvas)
        // SPEC: docs/spec.md — a blur with nothing to read fails closed.
        guard let settings = shape.blur, let source else {
            return context.fill(bitten, with: .color(.black), style: style)
        }
        context.drawLayer { outer in
            outer.clip(to: bitten, style: style)
            // WORKAROUND: filtered inside the clip the blur drags in transparency past the edge.
            outer.drawLayer { inner in
                switch settings.style {
                case .pixels:
                    guard let tiles = mosaics[settings.strength] else {
                        return inner.fill(bitten, with: .color(.black), style: style)
                    }
                    inner.draw(tiles, in: zoomed(whole))
                case .blur:
                    inner.addFilter(.blur(radius: MarkupBlur.radius(forStrength: settings.strength)
                                          * scale * zoom, options: .dithersResult))
                    inner.draw(source, in: zoomed(whole))
                }
            }
            if settings.mode == .around, settings.dim > 0 {
                outer.fill(Path(whole), with: .color(.black.opacity(Double(settings.dim) / 20)))
            }
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

    private func add(_ points: [CGPoint], to path: inout Path) {
        let marks = points.map { MarkupPoint(x: $0.x, y: $0.y) }
        for leg in MarkupGeometry.curves(through: marks) {
            path.addCurve(to: CGPoint(x: leg.to.x, y: leg.to.y),
                          control1: CGPoint(x: leg.control1.x, y: leg.control1.y),
                          control2: CGPoint(x: leg.control2.x, y: leg.control2.y))
        }
    }

    /// Curves through the points, not the corners between them: a mouse
    /// reports a chain of straight bits and a hand does not draw one.
    private func freehand(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        let marks = points.map { MarkupPoint(x: $0.x, y: $0.y) }
        for leg in MarkupGeometry.curves(through: marks) {
            path.addCurve(to: CGPoint(x: leg.to.x, y: leg.to.y),
                          control1: CGPoint(x: leg.control1.x, y: leg.control1.y),
                          control2: CGPoint(x: leg.control2.x, y: leg.control2.y))
        }
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
    var active = true

    func makeNSView(context: Context) -> NSView { CursorView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CursorView else { return }
        view.cursor = active ? MarkupCursors.cursor(for: tool, width: width) : nil
        view.wear()
    }

    final class CursorView: NSView {
        var cursor: NSCursor?
        private var area: NSTrackingArea?
        private var inside = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let fresh = NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate,
                          .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
            addTrackingArea(fresh)
            area = fresh
        }

        /// Set on every move, not only on entering. A cursor rect belongs to
        /// the view the pointer HIT, and this one is hit by nothing so that it
        /// cannot swallow the drawing; whatever is under it resets the arrow
        /// the moment it is asked to.
        func wear() {
            guard inside else { return }
            (cursor ?? .arrow).set()
        }

        override func mouseEntered(with event: NSEvent) { inside = true; wear() }
        override func mouseMoved(with event: NSEvent) { inside = true; wear() }
        override func mouseExited(with event: NSEvent) { inside = false }
        override func cursorUpdate(with event: NSEvent) { inside = true; wear() }
    }
}
