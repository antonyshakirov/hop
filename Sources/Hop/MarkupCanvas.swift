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
        .overlay(alignment: .topLeading) { typingField }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = MarkupPoint(x: value.location.x / scale, y: value.location.y / scale)
                    if surface.drafting == nil {
                        surface.begin(at: point)
                    } else {
                        surface.extend(to: point)
                    }
                }
                .onEnded { _ in surface.finish() }
        )
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
        context.stroke(segment(tail, tip), with: .color(colour), style: stroke)

        let head = MarkupGeometry.arrowHead(from: from, to: to, style: .solid, width: shape.ink.width)
        guard head.count == 3 else { return }
        var barb = Path()
        barb.move(to: CGPoint(x: head[0].x * scale, y: head[0].y * scale))
        barb.addLine(to: tip)
        barb.addLine(to: CGPoint(x: head[2].x * scale, y: head[2].y * scale))
        barb.addLine(to: CGPoint(x: head[1].x * scale, y: head[1].y * scale))
        barb.closeSubpath()
        context.fill(barb, with: .color(colour))
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
