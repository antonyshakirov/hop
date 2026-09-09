// Generates the app icon: the light variant of the canonical icon —
// a flat cream rounded plate with the four-line asterisk.
// Must stay in sync with assets/icon/hop-icon-light.svg and the in-app
// rendering in Sources/Hop/AppIcon.swift.
// Run: swift scripts/make-icon.swift out.png [size]
//
// The size is an argument because every size is DRAWN, never scaled down from
// 1024: sips averaged the round-capped rays with the cream behind them, and at
// 128pt the black asterisk came out soft and grey (Anton, 2026-09-09).
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size: CGFloat = CommandLine.arguments.count > 2
    ? CGFloat(Double(CommandLine.arguments[2]) ?? 1024) : 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

// Backplate — flat, inset like a standard macOS icon
let inset = size * 0.09766
let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let platePath = NSBezierPath(roundedRect: plate, xRadius: size * 0.18359, yRadius: size * 0.18359)
NSColor(red: 0.973, green: 0.968, blue: 0.955, alpha: 1).setFill()
platePath.fill()

// Four-line asterisk — Hop's signature mark
let center = NSPoint(x: size / 2, y: size / 2)
let radius = size * 0.17813
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
path.lineWidth = size * 0.04453
path.lineCapStyle = .round
NSColor.black.setStroke()
path.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    fputs("render failed\n", stderr)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("icon: \(outPath) \(Int(size))px")
