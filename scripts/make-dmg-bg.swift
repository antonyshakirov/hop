import AppKit

let width = 640.0
let height = 400.0
let scale = 2.0

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width * scale),
    pixelsHigh: Int(height * scale),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { fatalError("bitmap fail") }
rep.size = NSSize(width: width, height: height)

guard let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("context fail") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let backdrop = NSColor(red: 0.043, green: 0.043, blue: 0.043, alpha: 1)
let yellow = NSColor(red: 1.0, green: 0.839, blue: 0.039, alpha: 1)

backdrop.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

func dot(_ x: Double, _ y: Double, radius: Double, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
}

let gridStep = 20.0
for row in stride(from: gridStep / 2, to: height, by: gridStep) {
    for column in stride(from: gridStep / 2, to: width, by: gridStep) {
        dot(column, row, radius: 1.1, color: NSColor(white: 1, alpha: 0.12))
    }
}

// SPEC: docs/spec.md, "DMG window" — iconTop must match icon_locations in dmg-settings.py
let iconTop = 165.0
let axis = height - iconTop

// WORKAROUND: a window with a background picture makes Finder draw both icon
// labels in dark text whatever the system appearance is, so they need a pad
func labelPad(_ label: String, centerX: Double) {
    let font = NSFont.systemFont(ofSize: 13)
    let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
    let padWidth = textWidth + 26
    let rect = NSRect(x: centerX - padWidth / 2, y: axis - 97, width: padWidth, height: 26)
    NSColor(white: 0.93, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13).fill()
}
labelPad("Hop", centerX: 170)
labelPad("Applications", centerX: 470)

let tail = 268.0
let tip = 372.0
let spacing = (tip - tail) / 12

for index in 0...12 {
    dot(tail + spacing * Double(index), axis, radius: 2.5, color: yellow)
}

let diagonal = spacing / 2.0.squareRoot()
for step in 1...3 {
    let offset = diagonal * Double(step)
    dot(tip - offset, axis + offset, radius: 2.5, color: yellow)
    dot(tip - offset, axis - offset, radius: 2.5, color: yellow)
}

let text = "drag hop into applications" as NSString
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor(white: 1, alpha: 0.55),
    .kern: 0.6,
]
let textSize = text.size(withAttributes: attrs)
text.draw(at: NSPoint(x: (width - textSize.width) / 2, y: 92), withAttributes: attrs)

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png fail") }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/dmg-bg.png"
try! png.write(to: URL(fileURLWithPath: out))
print("background: \(out)")
