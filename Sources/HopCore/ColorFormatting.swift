import Foundation

/// How a picked color is written out. The three notations designers and
/// front-end developers actually paste; the choice is per user and sticks.
public enum ColorFormat: String, CaseIterable, Identifiable, Sendable {
    case hex, rgb, hsl

    public var id: String { rawValue }

    /// Short label for the format chips — the notation itself, not a
    /// translated word, so it needs no localization.
    public var label: String { rawValue }
}

/// Pure color notation: 8-bit sRGB components in, a pasteable string out.
/// Lives in HopCore so the arithmetic (especially the HSL conversion) is
/// unit-tested without an NSColor or a screen anywhere near it.
public enum ColorFormatting {
    /// Uppercase "#RRGGBB" — the form design tools and CSS both accept.
    public static func hex(r: Int, g: Int, b: Int) -> String {
        let (r, g, b) = clamped(r, g, b)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// CSS "rgb(51, 102, 153)".
    public static func rgb(r: Int, g: Int, b: Int) -> String {
        let (r, g, b) = clamped(r, g, b)
        return "rgb(\(r), \(g), \(b))"
    }

    /// CSS "hsl(210, 50%, 40%)". Hue is rounded to a whole degree,
    /// saturation and lightness to whole percent — nobody pastes more
    /// precision than that, and it keeps the string short.
    public static func hsl(r: Int, g: Int, b: Int) -> String {
        let (ri, gi, bi) = clamped(r, g, b)
        let rf = Double(ri) / 255, gf = Double(gi) / 255, bf = Double(bi) / 255
        let maxV = max(rf, gf, bf), minV = min(rf, gf, bf)
        let lightness = (maxV + minV) / 2
        let delta = maxV - minV

        var hue = 0.0
        var saturation = 0.0
        if delta > 0 {
            // a gray has no hue at all; only a real spread gets one
            saturation = delta / (1 - abs(2 * lightness - 1))
            switch maxV {
            case rf: hue = (gf - bf) / delta
            case gf: hue = 2 + (bf - rf) / delta
            default: hue = 4 + (rf - gf) / delta
            }
            hue *= 60
            if hue < 0 { hue += 360 }
        }
        // 359.6° must not round to 360 — that notation reads as a second turn
        let degrees = Int(hue.rounded()) % 360
        return "hsl(\(degrees), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
    }

    /// The picked color in the user's chosen notation.
    public static func string(_ format: ColorFormat, r: Int, g: Int, b: Int) -> String {
        switch format {
        case .hex: return hex(r: r, g: g, b: b)
        case .rgb: return rgb(r: r, g: g, b: b)
        case .hsl: return hsl(r: r, g: g, b: b)
        }
    }

    /// Canonical storage form for a history entry: bare uppercase "RRGGBB",
    /// no "#". Kept beside the pasteable text so the row can draw the swatch
    /// no matter which notation the text uses.
    public static func canonical(r: Int, g: Int, b: Int) -> String {
        let (r, g, b) = clamped(r, g, b)
        return String(format: "%02X%02X%02X", r, g, b)
    }

    /// Inverse of `canonical` — also accepts a leading "#" and the 3-digit
    /// shorthand, so a hand-edited history entry still draws its swatch.
    /// Returns nil for anything that isn't a hex color.
    public static func components(_ raw: String) -> (r: Int, g: Int, b: Int)? {
        var digits = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit),
              let value = Int(digits, radix: 16) else { return nil }
        return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }

    private static func clamped(_ r: Int, _ g: Int, _ b: Int) -> (Int, Int, Int) {
        (min(max(r, 0), 255), min(max(g, 0), 255), min(max(b, 0), 255))
    }
}
