import CoreGraphics
import Foundation

/// A minimal SVG path (`d` attribute) parser. It tokenizes a path string and
/// returns a flat list of absolute drawing operations, converting every curve
/// family (quadratic, smooth, elliptical arc) into cubic Béziers so a renderer
/// only has to handle move / line / cubic / close.
///
/// The parser is deliberately dependency-free and works on the raw characters
/// so it copes with the compact encodings real icon sets emit: no-space
/// negatives (`.079-.2307`), leading-dot decimals (`.0729`), a command letter
/// glued to its first number, and a single command letter followed by several
/// coordinate sets (the command repeats; after `M`/`m` the repeats are `L`/`l`).
public enum SVGPath {
    /// One absolute drawing operation.
    public enum Op: Equatable, Sendable {
        case move(CGPoint)
        case line(CGPoint)
        case cubic(c1: CGPoint, c2: CGPoint, end: CGPoint)
        case close
    }

    /// Parse a path `d` string into absolute drawing ops. Unknown input is
    /// skipped rather than throwing so a malformed tail never loses the marks
    /// that parsed cleanly before it.
    public static func parse(_ d: String) -> [Op] {
        var scanner = Scanner(d)
        var ops: [Op] = []

        // Current point and the start of the current subpath (target of Z).
        var curX = 0.0, curY = 0.0
        var startX = 0.0, startY = 0.0
        // Second control point of the previous cubic (C/S) and control point of
        // the previous quadratic (Q/T); used to reflect for smooth S/T. Non-nil
        // only when the immediately preceding command was of the same family.
        var prevCubic: (x: Double, y: Double)?
        var prevQuad: (x: Double, y: Double)?

        while let cmd = scanner.nextCommand() {
            let rel = cmd.isLowercase
            switch cmd {
            case "M", "m":
                var first = true
                while let x = scanner.readNumber(), let y = scanner.readNumber() {
                    let ax = rel ? curX + x : x
                    let ay = rel ? curY + y : y
                    if first {
                        ops.append(.move(CGPoint(x: ax, y: ay)))
                        startX = ax; startY = ay
                        first = false
                    } else {
                        // Extra coordinate sets after a moveto are implicit linetos.
                        ops.append(.line(CGPoint(x: ax, y: ay)))
                    }
                    curX = ax; curY = ay
                }
                prevCubic = nil; prevQuad = nil

            case "L", "l":
                while let x = scanner.readNumber(), let y = scanner.readNumber() {
                    let ax = rel ? curX + x : x
                    let ay = rel ? curY + y : y
                    ops.append(.line(CGPoint(x: ax, y: ay)))
                    curX = ax; curY = ay
                }
                prevCubic = nil; prevQuad = nil

            case "H", "h":
                while let x = scanner.readNumber() {
                    let ax = rel ? curX + x : x
                    ops.append(.line(CGPoint(x: ax, y: curY)))
                    curX = ax
                }
                prevCubic = nil; prevQuad = nil

            case "V", "v":
                while let y = scanner.readNumber() {
                    let ay = rel ? curY + y : y
                    ops.append(.line(CGPoint(x: curX, y: ay)))
                    curY = ay
                }
                prevCubic = nil; prevQuad = nil

            case "C", "c":
                while let x1 = scanner.readNumber(), let y1 = scanner.readNumber(),
                      let x2 = scanner.readNumber(), let y2 = scanner.readNumber(),
                      let ex = scanner.readNumber(), let ey = scanner.readNumber() {
                    let c1x = rel ? curX + x1 : x1
                    let c1y = rel ? curY + y1 : y1
                    let c2x = rel ? curX + x2 : x2
                    let c2y = rel ? curY + y2 : y2
                    let endX = rel ? curX + ex : ex
                    let endY = rel ? curY + ey : ey
                    ops.append(.cubic(c1: CGPoint(x: c1x, y: c1y),
                                      c2: CGPoint(x: c2x, y: c2y),
                                      end: CGPoint(x: endX, y: endY)))
                    curX = endX; curY = endY
                    prevCubic = (c2x, c2y)
                }
                prevQuad = nil

            case "S", "s":
                while let x2 = scanner.readNumber(), let y2 = scanner.readNumber(),
                      let ex = scanner.readNumber(), let ey = scanner.readNumber() {
                    // First control point is the reflection of the previous
                    // cubic's second control point about the current point;
                    // if there was none, it coincides with the current point.
                    let c1x: Double, c1y: Double
                    if let pc = prevCubic {
                        c1x = 2 * curX - pc.x
                        c1y = 2 * curY - pc.y
                    } else {
                        c1x = curX; c1y = curY
                    }
                    let c2x = rel ? curX + x2 : x2
                    let c2y = rel ? curY + y2 : y2
                    let endX = rel ? curX + ex : ex
                    let endY = rel ? curY + ey : ey
                    ops.append(.cubic(c1: CGPoint(x: c1x, y: c1y),
                                      c2: CGPoint(x: c2x, y: c2y),
                                      end: CGPoint(x: endX, y: endY)))
                    curX = endX; curY = endY
                    prevCubic = (c2x, c2y)
                }
                prevQuad = nil

            case "Q", "q":
                while let qx = scanner.readNumber(), let qy = scanner.readNumber(),
                      let ex = scanner.readNumber(), let ey = scanner.readNumber() {
                    let ctrlX = rel ? curX + qx : qx
                    let ctrlY = rel ? curY + qy : qy
                    let endX = rel ? curX + ex : ex
                    let endY = rel ? curY + ey : ey
                    appendQuadratic(&ops, p0x: curX, p0y: curY,
                                    qx: ctrlX, qy: ctrlY, p1x: endX, p1y: endY)
                    curX = endX; curY = endY
                    prevQuad = (ctrlX, ctrlY)
                }
                prevCubic = nil

            case "T", "t":
                while let ex = scanner.readNumber(), let ey = scanner.readNumber() {
                    // Reflect the previous quadratic control point about current.
                    let ctrlX: Double, ctrlY: Double
                    if let pq = prevQuad {
                        ctrlX = 2 * curX - pq.x
                        ctrlY = 2 * curY - pq.y
                    } else {
                        ctrlX = curX; ctrlY = curY
                    }
                    let endX = rel ? curX + ex : ex
                    let endY = rel ? curY + ey : ey
                    appendQuadratic(&ops, p0x: curX, p0y: curY,
                                    qx: ctrlX, qy: ctrlY, p1x: endX, p1y: endY)
                    curX = endX; curY = endY
                    prevQuad = (ctrlX, ctrlY)
                }
                prevCubic = nil

            case "A", "a":
                while let rx = scanner.readNumber(), let ry = scanner.readNumber(),
                      let rot = scanner.readNumber(),
                      let laf = scanner.readFlag(), let sf = scanner.readFlag(),
                      let ex = scanner.readNumber(), let ey = scanner.readNumber() {
                    let endX = rel ? curX + ex : ex
                    let endY = rel ? curY + ey : ey
                    ops.append(contentsOf: arcToCubics(
                        p0x: curX, p0y: curY, p1x: endX, p1y: endY,
                        rx: rx, ry: ry, xAxisRotationDeg: rot,
                        largeArc: laf != 0, sweep: sf != 0))
                    curX = endX; curY = endY
                }
                prevCubic = nil; prevQuad = nil

            case "Z", "z":
                ops.append(.close)
                curX = startX; curY = startY
                prevCubic = nil; prevQuad = nil

            default:
                break
            }
        }
        return ops
    }

    // MARK: - Quadratic → cubic

    /// Elevate a quadratic Bézier to an equivalent cubic and append it.
    private static func appendQuadratic(_ ops: inout [Op],
                                        p0x: Double, p0y: Double,
                                        qx: Double, qy: Double,
                                        p1x: Double, p1y: Double) {
        let c1x = p0x + 2.0 / 3.0 * (qx - p0x)
        let c1y = p0y + 2.0 / 3.0 * (qy - p0y)
        let c2x = p1x + 2.0 / 3.0 * (qx - p1x)
        let c2y = p1y + 2.0 / 3.0 * (qy - p1y)
        ops.append(.cubic(c1: CGPoint(x: c1x, y: c1y),
                          c2: CGPoint(x: c2x, y: c2y),
                          end: CGPoint(x: p1x, y: p1y)))
    }

    // MARK: - Elliptical arc → cubics (SVG spec F.6)

    /// Convert an elliptical arc segment to a sequence of cubic Béziers using
    /// the endpoint-to-center parameterization (SVG implementation notes F.6.5)
    /// with out-of-range radius correction (F.6.6.2). The arc is split into
    /// pieces of at most 90° and each piece approximated with one cubic.
    private static func arcToCubics(p0x: Double, p0y: Double,
                                    p1x: Double, p1y: Double,
                                    rx rxIn: Double, ry ryIn: Double,
                                    xAxisRotationDeg: Double,
                                    largeArc: Bool, sweep: Bool) -> [Op] {
        // Coincident endpoints: the arc collapses to nothing.
        if p0x == p1x && p0y == p1y { return [] }
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        // A zero radius degenerates to a straight line (F.6.2).
        if rx == 0 || ry == 0 {
            return [.line(CGPoint(x: p1x, y: p1y))]
        }

        let phi = xAxisRotationDeg * .pi / 180.0
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        // F.6.5.1 — midpoint of the chord, transformed into the ellipse frame.
        let dx = (p0x - p1x) / 2.0
        let dy = (p0y - p1y) / 2.0
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // F.6.6.2 — enlarge the radii if they are too small to span the chord.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = lambda.squareRoot()
            rx *= s
            ry *= s
        }

        // F.6.5.2 — center in the ellipse frame.
        let rx2 = rx * rx, ry2 = ry * ry
        let x1p2 = x1p * x1p, y1p2 = y1p * y1p
        var numerator = rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2
        if numerator < 0 { numerator = 0 }
        let denominator = rx2 * y1p2 + ry2 * x1p2
        var coef = (numerator / denominator).squareRoot()
        if largeArc == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)

        // F.6.5.3 — center in the original coordinate system.
        let cx = cosPhi * cxp - sinPhi * cyp + (p0x + p1x) / 2.0
        let cy = sinPhi * cxp + cosPhi * cyp + (p0y + p1y) / 2.0

        // F.6.5.5/6 — start angle and sweep angle.
        func vectorAngle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = ((ux * ux + uy * uy) * (vx * vx + vy * vy)).squareRoot()
            var a = acos(max(-1.0, min(1.0, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let ux = (x1p - cxp) / rx
        let uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx
        let vy = (-y1p - cyp) / ry
        let theta1 = vectorAngle(1, 0, ux, uy)
        var dTheta = vectorAngle(ux, uy, vx, vy)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        // Split into ≤ 90° segments and emit one cubic per segment.
        let segments = max(1, Int((abs(dTheta) / (.pi / 2)).rounded(.up)))
        let delta = dTheta / Double(segments)
        let k = 4.0 / 3.0 * tan(delta / 4.0)

        // A point on the (rotated, translated) ellipse at parameter angle.
        func ellipsePoint(_ angle: Double) -> (Double, Double) {
            let ex = rx * cos(angle)
            let ey = ry * sin(angle)
            return (cosPhi * ex - sinPhi * ey + cx, sinPhi * ex + cosPhi * ey + cy)
        }
        // The derivative direction on the ellipse at parameter angle.
        func ellipseDerivative(_ angle: Double) -> (Double, Double) {
            let dxu = -rx * sin(angle)
            let dyu = ry * cos(angle)
            return (cosPhi * dxu - sinPhi * dyu, sinPhi * dxu + cosPhi * dyu)
        }

        var result: [Op] = []
        var angleStart = theta1
        for _ in 0..<segments {
            let angleEnd = angleStart + delta
            let (e1x, e1y) = ellipsePoint(angleStart)
            let (e2x, e2y) = ellipsePoint(angleEnd)
            let (d1x, d1y) = ellipseDerivative(angleStart)
            let (d2x, d2y) = ellipseDerivative(angleEnd)
            result.append(.cubic(
                c1: CGPoint(x: e1x + k * d1x, y: e1y + k * d1y),
                c2: CGPoint(x: e2x - k * d2x, y: e2y - k * d2y),
                end: CGPoint(x: e2x, y: e2y)))
            angleStart = angleEnd
        }
        return result
    }

    // MARK: - Tokenizer

    /// A character cursor over the path string. All numeric scanning happens
    /// here so the command handlers above stay declarative.
    private struct Scanner {
        private let chars: [Character]
        private var i = 0

        init(_ s: String) { chars = Array(s) }

        private static func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }

        private static func isCommand(_ c: Character) -> Bool {
            "MmLlHhVvCcSsQqTtAaZz".contains(c)
        }

        /// Skip SVG whitespace and comma separators.
        private mutating func skipSeparators() {
            while i < chars.count {
                let c = chars[i]
                if c == " " || c == "\t" || c == "\n" || c == "\r"
                    || c == "\u{0C}" || c == "," {
                    i += 1
                } else {
                    break
                }
            }
        }

        /// Consume and return the next command letter, or nil if the next
        /// meaningful character is not one.
        mutating func nextCommand() -> Character? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = chars[i]
            guard Scanner.isCommand(c) else { return nil }
            i += 1
            return c
        }

        /// Consume and return the next number, or nil if the next token is not a
        /// number. Handles leading-dot decimals, glued signs, and exponents.
        mutating func readNumber() -> Double? {
            skipSeparators()
            let saved = i
            guard i < chars.count else { return nil }

            var s = ""
            if chars[i] == "+" || chars[i] == "-" {
                s.append(chars[i]); i += 1
            }
            var sawDigit = false
            var sawDot = false
            while i < chars.count {
                let c = chars[i]
                if Scanner.isDigit(c) {
                    s.append(c); i += 1; sawDigit = true
                } else if c == "." && !sawDot {
                    // A second dot begins a new number, so stop at it.
                    sawDot = true; s.append(c); i += 1
                } else {
                    break
                }
            }
            // Optional exponent, only consumed when it has at least one digit.
            if i < chars.count && (chars[i] == "e" || chars[i] == "E") {
                var j = i + 1
                var exp = String(chars[i])
                if j < chars.count && (chars[j] == "+" || chars[j] == "-") {
                    exp.append(chars[j]); j += 1
                }
                var expDigits = false
                while j < chars.count && Scanner.isDigit(chars[j]) {
                    exp.append(chars[j]); j += 1; expDigits = true
                }
                if expDigits { s += exp; i = j }
            }

            guard sawDigit else { i = saved; return nil }
            // Tolerate a trailing dot (e.g. "5.") which Double(_:) rejects.
            if s.hasSuffix(".") { s.removeLast() }
            guard let value = Double(s) else { i = saved; return nil }
            return value
        }

        /// Read an arc flag: a single `0` or `1`, which may be packed with no
        /// separator against the next token. Falls back to a full number for
        /// lenient producers.
        mutating func readFlag() -> Double? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = chars[i]
            if c == "0" { i += 1; return 0 }
            if c == "1" { i += 1; return 1 }
            return readNumber()
        }
    }
}
