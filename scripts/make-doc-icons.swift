// Generates one iconset per document type Hop can open: a sheet of paper with
// a folded corner, Hop's asterisk, and the format on an ink band at the foot.
// A document must never look like a copy of the app (Anton, 2026-07-27) — the
// app icon is a cream plate, these are paper, and the band names the format so
// a folder full of them reads at a glance.
//
// Every size is drawn at its own scale rather than downsampled, so the band
// stays crisp. Below 64pt the label is dropped: the text would be a smudge at
// that size, and Finder always shows the file name next to a small icon.
//
// Run: swift scripts/make-doc-icons.swift <output-dir>
import AppKit

struct DocType {
    let iconName: String
    let label: String
}

// Must stay in sync with CFBundleDocumentTypes in scripts/Info.plist.
let types = [
    DocType(iconName: "DocTorrent", label: "TORRENT"),
    DocType(iconName: "DocRar", label: "RAR"),
    DocType(iconName: "DocZip", label: "ZIP"),
    DocType(iconName: "Doc7z", label: "7Z"),
    DocType(iconName: "DocTar", label: "TAR"),
    DocType(iconName: "DocGz", label: "GZ"),
    DocType(iconName: "DocTgz", label: "TGZ"),
    DocType(iconName: "DocBz2", label: "BZ2"),
    DocType(iconName: "DocXz", label: "XZ"),
]

/// icns slots: every entry is (pixel size, file name inside the iconset).
let slots: [(CGFloat, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

/// The label is legible from here up; below it the band stays blank.
let labelThreshold: CGFloat = 64

let cream = NSColor(red: 0.973, green: 0.968, blue: 0.955, alpha: 1)
let ink = NSColor(white: 0.05, alpha: 1)
let paper = NSColor(white: 1.0, alpha: 1)
let edge = NSColor(white: 0.72, alpha: 1)
let flapFill = NSColor(white: 0.87, alpha: 1)

/// Hop's four-line asterisk — the same construction as the app icon.
func drawAsterisk(in box: NSRect) {
    let center = NSPoint(x: box.midX, y: box.midY)
    let radius = box.width * 0.38
    let path = NSBezierPath()
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4 + .pi / 8
        path.move(to: center)
        path.line(to: NSPoint(x: center.x + cos(angle) * radius,
                              y: center.y + sin(angle) * radius))
    }
    path.lineWidth = max(1, box.width * 0.095)
    path.lineCapStyle = .round
    ink.setStroke()
    path.stroke()
}

/// The sheet: rounded on three corners, cut and folded on the top right.
func sheetPaths(_ r: NSRect, fold: CGFloat) -> (body: NSBezierPath, flap: NSBezierPath) {
    let radius = r.width * 0.055
    let body = NSBezierPath()
    body.move(to: NSPoint(x: r.minX + radius, y: r.minY))
    body.line(to: NSPoint(x: r.maxX - radius, y: r.minY))
    body.appendArc(withCenter: NSPoint(x: r.maxX - radius, y: r.minY + radius),
                   radius: radius, startAngle: -90, endAngle: 0)
    body.line(to: NSPoint(x: r.maxX, y: r.maxY - fold))
    body.line(to: NSPoint(x: r.maxX - fold, y: r.maxY))
    body.line(to: NSPoint(x: r.minX + radius, y: r.maxY))
    body.appendArc(withCenter: NSPoint(x: r.minX + radius, y: r.maxY - radius),
                   radius: radius, startAngle: 90, endAngle: 180)
    body.line(to: NSPoint(x: r.minX, y: r.minY + radius))
    body.appendArc(withCenter: NSPoint(x: r.minX + radius, y: r.minY + radius),
                   radius: radius, startAngle: 180, endAngle: 270)
    body.close()

    let flap = NSBezierPath()
    flap.move(to: NSPoint(x: r.maxX - fold, y: r.maxY))
    flap.line(to: NSPoint(x: r.maxX - fold, y: r.maxY - fold))
    flap.line(to: NSPoint(x: r.maxX, y: r.maxY - fold))
    flap.close()
    return (body, flap)
}

/// Shrink the type until the widest label fits the band, then centre it. The
/// margins are generous on purpose: a long format like TORRENT pressed against
/// both edges reads as cramped even when it technically fits (Anton, 2026-07-27).
func drawLabel(_ text: String, in band: NSRect) {
    let available = band.width * 0.70
    var size = band.height * 0.56
    var attrs: [NSAttributedString.Key: Any] = [:]
    var measured = NSSize.zero
    while size > 4 {
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        attrs = [.font: font, .foregroundColor: cream, .kern: size * 0.02]
        measured = (text as NSString).size(withAttributes: attrs)
        if measured.width <= available { break }
        size -= 0.5
    }
    let origin = NSPoint(x: band.midX - measured.width / 2,
                         y: band.midY - measured.height / 2)
    (text as NSString).draw(at: origin, withAttributes: attrs)
}

func render(_ type: DocType, size: CGFloat) -> Data {
    // An explicit bitmap rather than NSImage.lockFocus: on a Retina Mac locking
    // focus rasterizes at the backing scale, so every slot came out at twice its
    // pixel size and iconutil silently filed them under the wrong sizes.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else {
        fputs("no bitmap for \(type.iconName) at \(size)\n", stderr)
        exit(1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let sheet = NSRect(x: size * 0.14, y: size * 0.04, width: size * 0.72, height: size * 0.92)
    let (body, flap) = sheetPaths(sheet, fold: sheet.width * 0.24)

    paper.setFill()
    body.fill()

    let band = NSRect(x: sheet.minX, y: sheet.minY,
                      width: sheet.width, height: sheet.height * 0.27)
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    ink.setFill()
    band.fill()
    NSGraphicsContext.restoreGraphicsState()

    flapFill.setFill()
    flap.fill()

    // The outline last, so neither the band nor the flap paints over it. Without
    // it a white sheet vanishes into Finder's light background.
    edge.setStroke()
    body.lineWidth = max(1, size * 0.008)
    body.stroke()

    let mark = sheet.width * 0.50
    let paperTop = sheet.maxY
    let paperBottom = band.maxY
    drawAsterisk(in: NSRect(x: sheet.midX - mark / 2,
                            y: (paperBottom + paperTop) / 2 - mark / 2,
                            width: mark, height: mark))

    if size >= labelThreshold {
        drawLabel(type.label, in: band)
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fputs("render failed for \(type.iconName) at \(size)\n", stderr)
        exit(1)
    }
    return png
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let fm = FileManager.default

for type in types {
    let iconset = URL(fileURLWithPath: outDir).appendingPathComponent("\(type.iconName).iconset")
    try? fm.removeItem(at: iconset)
    try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    for (size, name) in slots {
        let png = render(type, size: size)
        try! png.write(to: iconset.appendingPathComponent(name))
    }
    print("iconset: \(type.iconName)")
}
