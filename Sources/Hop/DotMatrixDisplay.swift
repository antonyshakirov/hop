import SwiftUI

/// Display made of "lamp" dots in the interval spirit:
/// active dots glow with a halo, inactive ones barely emerge from the dark.
struct DotMatrixDisplay: View {
    let text: String
    let dimCount: Int
    let blinkOff: Bool
    var cell: CGFloat = 7.0 // compact mode passes a smaller value
    var highlight: Range<Int>? = nil // digit being edited — in yellow

    // light theme: without the glow the dots read worse — compensate with size
    private var dot: CGFloat { cell * (Theme.isDark ? 0.657 : 0.87) }
    // halos and "off" lamps only on large cells: in the mini preview
    // (cell ~2) the halo is bigger than the dot itself, smearing everything into noise
    private var showsGlow: Bool { dot >= 3 }

    var body: some View {
        let columns = DotFont.columns(for: text)
        Canvas { ctx, _ in
            let inset = (cell - dot) / 2

            // light theme: a solid yellow plate under the whole group being
            // edited (like a text selection) — yellow spots on every dot
            // looked dirty
            if !Theme.isDark, let highlight, !highlight.isEmpty, !blinkOff {
                var x = 0
                var startX: CGFloat?
                var endX: CGFloat = 0
                for (index, ch) in text.enumerated() {
                    let width = DotFont.glyph(for: ch).width
                    if highlight.contains(index) {
                        if startX == nil { startX = CGFloat(x) * cell }
                        endX = CGFloat(x + width) * cell
                    }
                    x += width + 1
                }
                if let startX {
                    let plate = CGRect(
                        x: startX - 2, y: -2,
                        width: endX - startX + 4, height: 7 * cell + 4
                    )
                    ctx.fill(
                        Path(roundedRect: plate, cornerRadius: 4),
                        with: .color(Color(nsColor: .systemYellow).opacity(0.45))
                    )
                }
            }

            var xCol = 0
            for (index, ch) in text.enumerated() {
                let glyph = DotFont.glyph(for: ch)
                let isDim = index < dimCount
                for row in 0..<7 {
                    for col in 0..<glyph.width {
                        let on = glyph.isOn(row: row, col: col)
                        let x = CGFloat(xCol + col) * cell + inset
                        let y = CGFloat(row) * cell + inset
                        let rect = CGRect(x: x, y: y, width: dot, height: dot)

                        let isEditing = highlight?.contains(index) ?? false
                        let haloInset = -dot * 0.37 // proportional to the dot
                        if on && !blinkOff && isEditing {
                            if Theme.isDark {
                                let halo = rect.insetBy(dx: haloInset, dy: haloInset)
                                ctx.fill(Path(ellipseIn: halo), with: .color(Theme.editing.opacity(0.25)))
                                ctx.fill(Path(ellipseIn: rect), with: .color(Theme.editing))
                            } else {
                                // light: dark dots on top of the yellow plate
                                ctx.fill(Path(ellipseIn: rect), with: .color(Theme.dotBright))
                            }
                        } else if on && !isDim && !blinkOff {
                            // halo under a bright dot — only on the large display
                            if showsGlow {
                                let halo = rect.insetBy(dx: haloInset, dy: haloInset)
                                ctx.fill(Path(ellipseIn: halo), with: .color(Theme.dotHalo))
                            }
                            ctx.fill(Path(ellipseIn: rect), with: .color(Theme.dotBright))
                        } else if on && !blinkOff {
                            ctx.fill(Path(ellipseIn: rect), with: .color(Theme.dotDim))
                        } else if isEditing {
                            // background of the digit being edited — matches the accent, no dirt
                            let tint = Theme.isDark
                                ? Theme.editing.opacity(0.14)
                                : Color.black.opacity(0.12) // on the yellow plate
                            ctx.fill(Path(ellipseIn: rect), with: .color(tint))
                        } else if showsGlow {
                            // background matrix grid — noise in the mini preview
                            ctx.fill(Path(ellipseIn: rect), with: .color(Theme.dotOff))
                        }
                    }
                }
                xCol += glyph.width + 1
            }
        }
        .frame(width: CGFloat(columns) * cell, height: 7 * cell)
    }
}
