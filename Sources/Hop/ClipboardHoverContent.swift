import AppKit
import SwiftUI

// SPEC: docs/spec.md — Clipboard, content-sized hover previews.
@MainActor
enum ClipboardHoverContent {
    static func text(_ value: String, rtl: Bool, maximum: NSSize) -> NSView {
        let font = rtl ? NSFont.systemFont(ofSize: 10) : NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let style = NSMutableParagraphStyle()
        style.alignment = rtl ? .right : .left
        style.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
        let text = NSAttributedString(string: value, attributes: [.font: font,
            .foregroundColor: NSColor(Theme.textPrimary), .paragraphStyle: style])
        let width = min(maximum.width, max(32, ceil(text.size().width) + 24))
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = font; label.attributedStringValue = text
        label.preferredMaxLayoutWidth = max(1, width - 20)
        let measured = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0,
            width: max(1, width - 20), height: 1_000_000)).height ?? font.ascender - font.descender
        let height = min(maximum.height, max(28, ceil(measured) + 18))
        let clipped = measured > height - 16
        label.maximumNumberOfLines = clipped
            ? max(1, Int((height - 16) / ceil(font.ascender - font.descender + font.leading))) : 0
        label.cell?.truncatesLastVisibleLine = clipped
        let content = background(NSSize(width: width, height: height))
        label.frame = content.bounds.insetBy(dx: 10, dy: 8)
        content.addSubview(label)
        return content
    }

    static func image(_ bitmap: ClipboardHoverBitmap, maximum: NSSize, scale: CGFloat) -> NSView? {
        let natural = NSSize(width: CGFloat(bitmap.image.width) / max(1, scale),
                             height: CGFloat(bitmap.image.height) / max(1, scale))
        let factor = min(1, min((maximum.width - 20) / natural.width, (maximum.height - 16) / natural.height))
        guard factor.isFinite, factor > 0 else { return nil }
        let size = NSSize(width: natural.width * factor, height: natural.height * factor)
        let content = background(NSSize(width: max(32, size.width + 20), height: max(28, size.height + 16)))
        let image = NSImageView(frame: NSRect(x: (content.bounds.width - size.width) / 2,
            y: (content.bounds.height - size.height) / 2, width: size.width, height: size.height))
        image.image = NSImage(cgImage: bitmap.image, size: natural)
        image.imageScaling = .scaleProportionallyDown
        content.addSubview(image)
        return content
    }

    private static func background(_ size: NSSize) -> NSView {
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true; content.layer?.cornerRadius = 8
        content.layer?.backgroundColor = NSColor(Theme.background).cgColor
        content.layer?.borderWidth = 0.5; content.layer?.borderColor = NSColor(Theme.divider).cgColor
        return content
    }
}
