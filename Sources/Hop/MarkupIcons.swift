import SwiftUI

/// The markup toolbar's glyphs, drawn on a 24×24 grid and scaled to the button.
///
/// The drawing tools are one family: each body is built upright and turned by
/// the same 45°, so no two of them lean differently. Every silhouette is ONE
/// closed outline — two shapes sharing an edge stroke that edge twice, and the
/// joint swells at 19 pt.
enum MarkupGlyph: String, CaseIterable {
    case crop, pencil, fadingInk, marker, arrow, line, rectangle, oval
    case steps, text, magnifier, blur, eraser
    case undo, redo, grip, cursor, clear, save, copy, close
    case dressing, watermark, weight
}

struct MarkupStroke {
    var path: Path
    var width: CGFloat = 1.4
    var filled: Bool = false
}

enum MarkupIcons {
    static func strokes(for glyph: MarkupGlyph) -> [MarkupStroke] {
        switch glyph {
        case .crop:
            return [stroke { $0.move(to: p(7, 2)); $0.addLine(to: p(7, 17)); $0.addLine(to: p(22, 17)) },
                    stroke { $0.move(to: p(2, 7)); $0.addLine(to: p(17, 7)); $0.addLine(to: p(17, 22)) }]

        case .pencil:
            return [stroke { $0.addPath(turned(pencilBody())) },
                    stroke { $0.addPath(turned(line(10.1, 13.3, 13.9, 13.3))) }]

        case .fadingInk:
            return [stroke { $0.addPath(turned(pencilBody())) },
                    stroke { $0.addPath(turned(line(10.1, 13.3, 13.9, 13.3))) },
                    dot(6.7, 18.5, 1.15), dot(4.5, 19.9, 0.85), dot(2.7, 21.1, 0.6)]

        case .marker:
            return [stroke { $0.addPath(turned(markerBody())) },
                    stroke(width: 2.8) { $0.addPath(line(5.6, 20.2, 15, 20.2)) }]

        case .eraser:
            return [stroke { $0.addPath(turned(rounded(8.3, 4.9, 7.4, 12.2, 1.8))) },
                    stroke { $0.addPath(turned(line(8.3, 12.1, 15.7, 12.1))) }]

        case .arrow:
            // The shaft stops short of the corner: a round cap ON the joint
            // pokes out of it as a bead.
            return [stroke { $0.addPath(line(5, 19, 17.6, 6.4)) },
                    stroke { $0.move(to: p(11.5, 5.5)); $0.addLine(to: p(18.5, 5.5)); $0.addLine(to: p(18.5, 12.5)) }]

        case .line:
            return [stroke { $0.addPath(line(4.5, 19.5, 19.5, 4.5)) }]

        case .rectangle:
            return [stroke { $0.addPath(rounded(3.5, 5.5, 17, 13, 2)) }]

        case .oval:
            return [stroke { $0.addEllipse(in: CGRect(x: 3.5, y: 5.5, width: 17, height: 13)) }]

        case .steps:
            return [stroke { $0.addEllipse(in: CGRect(x: 4.4, y: 4.4, width: 15.2, height: 15.2)) },
                    stroke { $0.move(to: p(10.5, 10.2)); $0.addLine(to: p(12, 8.7)); $0.addLine(to: p(12, 15.3)) }]

        case .text:
            return [stroke { $0.addPath(line(5.6, 6.8, 18.4, 6.8)) },
                    stroke { $0.addPath(line(12, 6.8, 12, 17.2)) }]

        case .magnifier:
            return [stroke { $0.addEllipse(in: CGRect(x: 4, y: 4, width: 13, height: 13)) },
                    stroke { $0.addPath(line(15.5, 15.5, 20.5, 20.5)) }]

        case .blur:
            return [stroke {
                $0.move(to: p(12, 3.4))
                $0.addCurve(to: p(18.2, 13.7), control1: p(12, 3.4), control2: p(18.2, 10))
                $0.addArc(center: p(12, 13.7), radius: 6.2, startAngle: .degrees(0),
                          endAngle: .degrees(180), clockwise: false)
                $0.addCurve(to: p(12, 3.4), control1: p(5.8, 10), control2: p(12, 3.4))
                $0.closeSubpath()
            }]

        case .undo:
            return [stroke { $0.move(to: p(8.5, 6.5)); $0.addLine(to: p(4, 11)); $0.addLine(to: p(8.5, 15.5)) },
                    stroke {
                        $0.move(to: p(4, 11)); $0.addLine(to: p(14, 11))
                        $0.addArc(center: p(14, 16.5), radius: 5.5, startAngle: .degrees(-90),
                                  endAngle: .degrees(90), clockwise: false)
                        $0.addLine(to: p(12, 22))
                    }]

        case .redo:
            return [stroke { $0.move(to: p(15.5, 6.5)); $0.addLine(to: p(20, 11)); $0.addLine(to: p(15.5, 15.5)) },
                    stroke {
                        $0.move(to: p(20, 11)); $0.addLine(to: p(10, 11))
                        $0.addArc(center: p(10, 16.5), radius: 5.5, startAngle: .degrees(-90),
                                  endAngle: .degrees(90), clockwise: true)
                        $0.addLine(to: p(12, 22))
                    }]

        case .grip:
            return [dot(9, 6, 1.1), dot(15, 6, 1.1), dot(9, 12, 1.1),
                    dot(15, 12, 1.1), dot(9, 18, 1.1), dot(15, 18, 1.1)]

        case .cursor:
            return [stroke {
                $0.move(to: p(5.5, 3.5)); $0.addLine(to: p(18.5, 10.9))
                $0.addLine(to: p(12.9, 12.1)); $0.addLine(to: p(10.9, 17.5))
                $0.closeSubpath()
            }]

        case .clear:
            return [stroke { $0.addPath(line(5, 7, 19, 7)) },
                    stroke { $0.move(to: p(9.5, 7)); $0.addLine(to: p(9.5, 4.5)); $0.addLine(to: p(14.5, 4.5)); $0.addLine(to: p(14.5, 7)) },
                    stroke { $0.move(to: p(7, 7)); $0.addLine(to: p(8, 19.5)); $0.addLine(to: p(16, 19.5)); $0.addLine(to: p(17, 7)) }]

        case .save:
            return [stroke { $0.addPath(line(12, 4, 12, 14.5)) },
                    stroke { $0.move(to: p(7.5, 11)); $0.addLine(to: p(12, 15)); $0.addLine(to: p(16.5, 11)) },
                    stroke { $0.addPath(line(4.5, 19.5, 19.5, 19.5)) }]

        case .copy:
            return [stroke { $0.addPath(rounded(8.5, 8.5, 11, 11, 2)) },
                    stroke { $0.move(to: p(15.5, 5.5)); $0.addLine(to: p(4.5, 5.5)); $0.addLine(to: p(4.5, 16.5)) }]

        case .close:
            return [stroke { $0.addPath(line(6, 6, 18, 18)) },
                    stroke { $0.addPath(line(18, 6, 6, 18)) }]

        case .weight:
            return [stroke(width: 1) { $0.addPath(line(4, 7, 20, 7)) },
                    stroke(width: 2.4) { $0.addPath(line(4, 12, 20, 12)) },
                    stroke(width: 4.4) { $0.addPath(line(4, 17.6, 20, 17.6)) }]

        case .dressing:
            return [stroke { $0.addPath(rounded(2.5, 4, 19, 16, 2.6)) },
                    stroke { $0.addPath(rounded(6, 7.5, 12, 9, 1.6)) }]

        case .watermark:
            return [stroke { $0.addPath(rounded(2.5, 4, 19, 16, 2.6)) },
                    stroke { $0.addPath(line(6, 15.5, 9.5, 8.5)) },
                    stroke { $0.addPath(line(10.5, 15.5, 14, 8.5)) },
                    stroke { $0.addPath(line(15, 15.5, 18.5, 8.5)) }]
        }
    }

    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private static func stroke(width: CGFloat = 1.4, _ build: (inout Path) -> Void) -> MarkupStroke {
        var path = Path()
        build(&path)
        return MarkupStroke(path: path, width: width)
    }

    private static func dot(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> MarkupStroke {
        var path = Path()
        path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        return MarkupStroke(path: path, width: 0, filled: true)
    }

    private static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
        var path = Path()
        path.move(to: p(x1, y1))
        path.addLine(to: p(x2, y2))
        return path
    }

    private static func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
    }

    private static func pencilBody() -> Path {
        var path = Path()
        path.move(to: p(9.9, 5.1))
        path.addLine(to: p(14.1, 5.1))
        path.addLine(to: p(14.1, 13.3))
        path.addLine(to: p(12, 17.7))
        path.addLine(to: p(9.9, 13.3))
        path.closeSubpath()
        return path
    }

    private static func markerBody() -> Path {
        var path = Path()
        path.move(to: p(9.9, 4.6))
        path.addLine(to: p(14.1, 4.6))
        path.addLine(to: p(14.1, 11.6))
        path.addLine(to: p(15.1, 11.6))
        path.addLine(to: p(13.4, 16.4))
        path.addLine(to: p(10.6, 16.4))
        path.addLine(to: p(8.9, 11.6))
        path.addLine(to: p(9.9, 11.6))
        path.closeSubpath()
        return path
    }

    private static func turned(_ path: Path) -> Path {
        let centre = CGAffineTransform(translationX: 12, y: 12)
        let transform = CGAffineTransform(translationX: -12, y: -12)
            .concatenating(CGAffineTransform(rotationAngle: .pi / 4))
            .concatenating(centre)
        return path.applying(transform)
    }
}

/// One glyph at the size a button gives it.
struct MarkupIcon: View {
    let glyph: MarkupGlyph
    var size: CGFloat = 19

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 24
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            // Every stroke is outlined and the lot filled ONCE. Stroking them
            // one by one paints the overlaps twice, and at anything below full
            // opacity the crossings show up as brighter joints.
            var silhouette = Path()
            for stroke in MarkupIcons.strokes(for: glyph) {
                let path = stroke.path.applying(transform)
                if stroke.filled {
                    silhouette.addPath(path)
                } else {
                    silhouette.addPath(path.strokedPath(
                        StrokeStyle(lineWidth: stroke.width * scale, lineCap: .round, lineJoin: .round)
                    ))
                }
            }
            context.fill(silhouette, with: .style(.foreground))
        }
        .frame(width: size, height: size)
    }
}
