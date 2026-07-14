import Foundation

/// Bitmap 5×7 font for the dot-matrix display.
/// Each row is a bitmask, most significant bit on the left.
enum DotFont {
    struct Glyph {
        let width: Int
        let rows: [UInt8] // 7 rows

        func isOn(row: Int, col: Int) -> Bool {
            (rows[row] >> (width - 1 - col)) & 1 == 1
        }
    }

    private static let glyphs: [Character: Glyph] = [
        "0": Glyph(width: 5, rows: [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110]),
        "1": Glyph(width: 5, rows: [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110]),
        "2": Glyph(width: 5, rows: [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111]),
        "3": Glyph(width: 5, rows: [0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110]),
        "4": Glyph(width: 5, rows: [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010]),
        "5": Glyph(width: 5, rows: [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110]),
        "6": Glyph(width: 5, rows: [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110]),
        "7": Glyph(width: 5, rows: [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000]),
        "8": Glyph(width: 5, rows: [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110]),
        "9": Glyph(width: 5, rows: [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100]),
        ":": Glyph(width: 1, rows: [0b0, 0b0, 0b1, 0b0, 0b1, 0b0, 0b0]),
    ]

    private static let blank = Glyph(width: 3, rows: [0, 0, 0, 0, 0, 0, 0])

    static func glyph(for ch: Character) -> Glyph {
        glyphs[ch] ?? blank
    }

    /// Total column count for a string with a 1-column gap between glyphs.
    static func columns(for text: String) -> Int {
        let widths = text.map { glyph(for: $0).width }
        return widths.reduce(0, +) + max(0, text.count - 1)
    }
}
