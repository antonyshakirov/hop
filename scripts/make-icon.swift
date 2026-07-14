// Generates the app icon: a dark rounded square,
// a dial arc of glowing dots in a dot-matrix display style.
// Run: swift scripts/make-icon.swift out.png
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Backplate — a rounded square with a subtle vertical gradient
let plate = NSRect(x: 96, y: 96, width: 832, height: 832)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 186, yRadius: 186)
NSGradient(colors: [
    NSColor(white: 0.11, alpha: 1),
    NSColor(white: 0.03, alpha: 1),
])!.draw(in: platePath, angle: -90)

// Glowing asterisk — Hop's signature mark
let center = NSPoint(x: 512, y: 512)
let radius: CGFloat = 265

func drawStar(lineWidth: CGFloat, color: NSColor) {
    color.setStroke()
    // one path for all rays — the translucent halo does not stack into stripes
    let path = NSBezierPath()
    for i in 0..<8 {
        // 8 rays rotated a half-step = 4 full slanted lines (no strict vertical)
        let angle = CGFloat(i) * .pi / 4 + .pi / 8
        path.move(to: center)
        path.line(to: NSPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        ))
    }
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.stroke()
}

// halo + bright mark
drawStar(lineWidth: 128, color: NSColor(white: 1, alpha: 0.13))
drawStar(lineWidth: 68, color: .white)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    fputs("render failed\n", stderr)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("icon: \(outPath)")
