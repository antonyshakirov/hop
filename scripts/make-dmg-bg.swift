// DMG window background: dark backdrop, dotted arrow and a caption.
// Draw at 1280×800 and set 144 dpi — Finder renders it crisply on Retina.
import AppKit

// scale as an argument: 1 → 640×400, 2 → 1280×800 (layers for a retina TIFF)
let scale = CGFloat(Double(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "2") ?? 2)
let size = NSSize(width: 640 * scale, height: 400 * scale)
let image = NSImage(size: size)
image.lockFocus()

NSColor(white: 0.043, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

// dotted arrow between the icon spots (icons at y≈400, centers x=340/940)
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 235 * scale, y: 205 * scale))
arrow.line(to: NSPoint(x: 395 * scale, y: 205 * scale))
arrow.lineWidth = 3 * scale
let dashes: [CGFloat] = [1 * scale, 11 * scale]
arrow.setLineDash(dashes, count: 2, phase: 0)
arrow.lineCapStyle = .round
NSColor(white: 0.42, alpha: 1).setStroke()
arrow.stroke()
// arrowhead — three dots in a wedge
for (dx, dy) in [(0, 0), (-13, 9), (-13, -9)] {
    let dot = NSRect(x: 405 * scale + CGFloat(dx) * scale - 2 * scale,
                     y: 205 * scale + CGFloat(dy) * scale - 2 * scale,
                     width: 4.5 * scale, height: 4.5 * scale)
    NSColor(white: 0.42, alpha: 1).setFill()
    NSBezierPath(ovalIn: dot).fill()
}

// caption bottom center, signature lowercase
let text = "drag hop into applications" as NSString
let font = NSFont.monospacedSystemFont(ofSize: 15 * scale, weight: .medium)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(white: 0.52, alpha: 1),
    .kern: 0.75 * scale,
]
let tsize = text.size(withAttributes: attrs)
text.draw(at: NSPoint(x: (size.width - tsize.width) / 2, y: 64 * scale), withAttributes: attrs)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else { fatalError("png fail") }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/dmg-bg.png"
try! png.write(to: URL(fileURLWithPath: out))
print("background: \(out)")
