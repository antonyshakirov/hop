// Generates the app icon: the light variant of the canonical icon —
// a flat cream rounded plate with the four-line asterisk.
// Must stay in sync with assets/icon/hop-icon-light.svg and the in-app
// rendering in Sources/Hop/AppIcon.swift.
// Run: swift scripts/make-icon.swift out.png
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Backplate — flat, inset like a standard macOS icon (2x the 512 design)
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 188, yRadius: 188)
NSColor(red: 0.973, green: 0.968, blue: 0.955, alpha: 1).setFill()
platePath.fill()

// Four-line asterisk — Hop's signature mark
let center = NSPoint(x: 512, y: 512)
let starBox = plate.insetBy(dx: 172, dy: 172)
let radius = starBox.width * 0.38
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
path.lineWidth = starBox.width * 0.095
path.lineCapStyle = .round
NSColor(white: 0.05, alpha: 1).setStroke()
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
print("icon: \(outPath)")
