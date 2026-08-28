import HopCore
import SwiftUI
import UniformTypeIdentifiers

/// Numeric field with free-form input: lets only digits through,
/// clamps to the range on submit/blur.
struct NumericField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var color: Color = Theme.textPrimary
    /// What this number is, on hover — a bare field says nothing once the label
    /// beside it has scrolled out of the eye's way.
    var help: String?
    /// Minimum digits shown, zero-padded. A clock field passes 2 so single-digit
    /// hours and minutes read as `09` rather than `9` — "22 : 0" is not a time.
    var padTo: Int = 0

    private func display(_ value: Int) -> String {
        let digits = "\(value)"
        guard digits.count < padTo else { return digits }
        return String(repeating: "0", count: padTo - digits.count) + digits
    }

    @State private var text = ""
    // Whether the user actually typed since gaining focus. A focus→blur with no
    // edit must NOT rewrite the value: the displayed text can be a clamp-on-read
    // of the stored value (e.g. a legacy 0 shown as the default), and committing
    // that on a bare blur would needlessly overwrite what is on disk.
    @State private var edited = false
    @FocusState private var focused: Bool

    var body: some View {
        // The chain below is long enough that the type-checker gives up when a
        // modifier is added to it directly, so the tooltip goes on the outside.
        field.helpIfAny(help)
    }

    private var field: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .font(Theme.mono(11, weight: .semibold))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            // No focus nudge: the compensation for AppKit's old field-editor
            // lift now IS the jump — clicking a field visibly dropped the digits
            // (Anton, 2026-07-28).
            .frame(width: 44, height: 24)
            .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 5))
            .onAppear { text = display(value) }
            .onChange(of: text) { _, new in
                let digits = String(new.filter(\.isNumber).prefix(3))
                if digits != new { text = digits; return }
                // only a live edit (focused) owns the value; programmatic
                // reformats (onAppear, value/preview sync) must not parse back.
                guard focused else { return }
                edited = true
                if let v = Int(digits), range.contains(v) { value = v }
            }
            .onChange(of: value) { _, v in
                if !focused { text = display(v) }
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused { edited = false; return }
                if edited, let v = Int(text) {
                    value = min(max(v, range.lowerBound), range.upperBound)
                }
                text = display(value)
                edited = false
            }
            .onSubmit {
                if edited, let v = Int(text) {
                    value = min(max(v, range.lowerBound), range.upperBound)
                }
                text = display(value)
                edited = false
            }
    }
}

/// "visible rows" chooser for the to-do and tracker modules: a single always-active
/// numeric field (range 3…15), sharing `NumericField` with the clipboard's
/// setting. The "all"/unlimited option is gone (`RowCap` always caps). A stored 0
/// — the previous "all" sentinel — reads as the default so nothing needs
/// migrating; any edit writes a clamped 3…15 count.
struct VisibleRowsField: View {
    @Binding var stored: Int

    var body: some View {
        NumericField(value: Binding(
            get: { RowCap.cap(stored) },
            set: { stored = min(max($0, RowCap.minRows), RowCap.maxRows) }
        ), range: RowCap.minRows...RowCap.maxRows)
    }
}

/// Torrent speed-limit entry: a free-form field bound to a CANONICAL KB/s value,
/// shown and entered in the chosen unit (KB/s or MB/s). KB mode accepts up to 6
/// digits; MB mode accepts up to 4 integer digits plus one optional decimal
/// (e.g. 12.5). Empty / 0 = unlimited (kept). Toggling the unit reformats the
/// displayed value in place; the stored KB/s never changes. Conversion, parsing
/// and clamping live in `HopCore.RateLimit` (tested). A ZERO value (= no limit,
/// including one the user just typed) renders in the tertiary/placeholder gray so
/// it reads as "off"; any non-zero value uses the normal active color.
struct RateLimitField: View {
    @Binding var kb: Int
    let unit: RateUnit
    var color: Color = Theme.textPrimary

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        // kb is kept in sync with the field live while typing, so 0 (empty or a
        // typed "0") dims the text the instant it becomes unlimited.
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .font(Theme.mono(11, weight: .semibold))
            .foregroundStyle(kb == 0 ? Theme.textTertiary : color)
            .multilineTextAlignment(.center)
            // the AppKit field editor lifts the text ~1.5px on focus (matches
            // NumericField) — compensate so the digit doesn't hop
            .offset(y: focused ? 1.5 : 0)
            .frame(width: 56, height: 24)
            .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 5))
            .onAppear { text = RateLimit.display(kb: kb, unit: unit) }
            // unit toggled by the parent: reformat the SAME canonical value in the
            // new unit. DISPLAY only — it must never rewrite kb, or merely viewing
            // 1234 KB/s as MB would round the stored value to 1200.
            .onChange(of: unit) { _, u in text = RateLimit.display(kb: kb, unit: u) }
            .onChange(of: text) { _, new in
                // only WHILE TYPING does the field own the value. The programmatic
                // reformats below (unit / kb changes) also fire this handler, so the
                // focus guard keeps them display-only and never parses back into kb.
                guard focused else { return }
                let filtered = Self.filter(new, unit: unit)
                if filtered != new { text = filtered; return }
                if let v = RateLimit.parse(filtered, unit: unit) { kb = v }
            }
            .onChange(of: kb) { _, v in
                if !focused { text = RateLimit.display(kb: v, unit: unit) }
            }
            .onChange(of: focused) { _, isFocused in
                // kb was already updated live while typing; on blur just normalize
                // the display ("1." → "1000", "1.20" → "1.2").
                if !isFocused { text = RateLimit.display(kb: kb, unit: unit) }
            }
    }

    /// Keep only the characters valid for the unit and cap the digit count:
    /// KB — up to 6 digits; MB — up to 4 integer digits + one dot + one decimal.
    private static func filter(_ raw: String, unit: RateUnit) -> String {
        switch unit {
        case .kb:
            return String(raw.filter(\.isNumber).prefix(6))
        case .mb:
            var seenDot = false, intDigits = 0, fracDigits = 0
            var out = ""
            for ch in raw {
                if ch.isNumber {
                    if seenDot {
                        guard fracDigits < 1 else { continue }
                        fracDigits += 1
                    } else {
                        guard intDigits < 4 else { continue }
                        intDigits += 1
                    }
                    out.append(ch)
                } else if ch == ".", !seenDot {
                    seenDot = true
                    out.append(ch)
                }
            }
            return out
        }
    }
}

/// Threshold row: two free-form fields, red is always stricter than yellow
/// (regular metrics: red > yellow; battery is inverted: red < yellow).
struct ThresholdRow: View {
    let label: String
    @Binding var yellow: Int
    @Binding var red: Int
    let maxValue: Int
    var inverted = false

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            NumericField(value: $yellow, range: 1...maxValue, color: Theme.accentYellow)
            NumericField(value: $red, range: 1...maxValue, color: Theme.accentRed)
        }
        .onChange(of: yellow) { _, y in
            if !inverted, y >= red { red = min(maxValue, y + 1) }
            if inverted, y <= red { red = max(1, y - 1) }
        }
        .onChange(of: red) { _, r in
            if !inverted, r <= yellow { yellow = max(1, r - 1) }
            if inverted, r >= yellow { yellow = min(maxValue, r + 1) }
        }
    }
}

/// Target for NSMenu items built from SwiftUI (language picker etc.).
final class MenuPickTarget: NSObject {
    private let handler: (String) -> Void

    init(_ handler: @escaping (String) -> Void) {
        self.handler = handler
    }

    @objc func pick(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String {
            handler(raw)
        }
    }
}

/// Link in the about footer: looks like plain text,
/// turns white with an underline on hover.
struct FooterLink: View {
    let url: String
    var label = "antonshakirov.com"
    // the footer's own link size; the donation CTA passes a bolder font.
    var font: Font = Theme.mono(11)
    @State private var hovering = false

    var body: some View {
        Button {
            if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        } label: {
            Text(label)
                .font(font)
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                .underline(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .help(label)
    }
}

/// Unified section switcher (settings, about): equal widths,
/// constant background, the same hover everywhere.
/// Panel-style slider: the system Slider doesn't render in snapshots
/// and clashes with the dot-matrix style.
struct MiniSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var width: CGFloat = 110

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                let span = CGFloat(range.upperBound - range.lowerBound)
                let fraction = CGFloat(value - range.lowerBound) / span
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.switchOffBg)
                        .frame(height: 3)
                    Capsule()
                        .fill(Theme.textSecondary)
                        .frame(width: max(0, fraction * geo.size.width), height: 3)
                    Circle()
                        .fill(.white)
                        .frame(width: 11, height: 11)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                        .offset(x: fraction * (geo.size.width - 11))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let f = min(1, max(0, gesture.location.x / geo.size.width))
                            value = range.lowerBound + Int((f * span).rounded())
                        }
                )
            }
            .frame(width: width, height: 14)
            Text("\(value)")
                .font(Theme.mono(10, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}

/// Metric chart in the iStat spirit (Anton, 2026-07-15): a full-width
/// filled area right under the metric's row — no scale, no legend, no
/// time labels. The row above already shows the current value; the shape
/// only conveys the trend. The first series is the filled primary, any
/// further series (temperature, upload) draw as thinner plain lines.
struct SparklineCard: View {
    struct Series: Identifiable {
        let label: String // identity only — never rendered
        let points: [SystemStatsController.HistoryPoint]
        let color: Color
        let maxValue: Double
        var dashed = false
        var id: String { label }
    }

    let series: [Series]
    /// Time window: points are placed by their timestamps, not at equal steps —
    /// history accumulates in the background and is shown "as is", without stretching.
    let start: Date
    let end: Date
    /// Tiny marker in the corner for paired charts (network ↓/↑) —
    /// two identical areas would otherwise be indistinguishable.
    var cornerSymbol: String?
    var height: CGFloat = 34

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(series.enumerated()), id: \.element.id) { index, s in
                if index == 0 {
                    AreaPath(points: s.points, maxValue: s.maxValue, start: start, end: end)
                        .fill(LinearGradient(
                            colors: [s.color.opacity(0.4), s.color.opacity(0.06)],
                            startPoint: .top, endPoint: .bottom
                        ))
                }
                LinePath(points: s.points, maxValue: s.maxValue, start: start, end: end)
                    .stroke(
                        s.color.opacity(index == 0 ? 1 : 0.55),
                        style: StrokeStyle(
                            lineWidth: index == 0 ? 1.5 : 1,
                            dash: s.dashed ? [3, 2.5] : []
                        )
                    )
            }
            if let symbol = cornerSymbol, let color = series.first?.color {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.leading, 2)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }
}

/// The line's silhouette closed down to the chart floor — the fill under the curve.
struct AreaPath: Shape {
    let points: [SystemStatsController.HistoryPoint]
    let maxValue: Double
    let start: Date
    let end: Date

    func path(in rect: CGRect) -> Path {
        var path = LinePath(points: points, maxValue: maxValue, start: start, end: end)
            .path(in: rect)
        guard !path.isEmpty, let last = path.currentPoint else { return path }
        path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        if let firstX = path.boundingRect.minX as CGFloat? {
            path.addLine(to: CGPoint(x: firstX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

struct LinePath: Shape {
    let points: [SystemStatsController.HistoryPoint]
    let maxValue: Double
    let start: Date
    let end: Date

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let span = end.timeIntervalSince(start)
        guard points.count > 1, maxValue > 0, span > 0 else { return path }
        var started = false
        for point in points {
            let fraction = point.t.timeIntervalSince(start) / span
            let x = rect.minX + CGFloat(min(max(fraction, 0), 1)) * rect.width
            let y = rect.maxY - CGFloat(min(max(point.v / maxValue, 0), 1)) * rect.height
            if started {
                path.addLine(to: CGPoint(x: x, y: y))
            } else {
                path.move(to: CGPoint(x: x, y: y))
                started = true
            }
        }
        return path
    }
}

/// THE single chip toggle: one size across the whole app. The reference is
/// "timer size": height 28, corner radius 5, mono 10 text / 13 icon.
/// New chips go ONLY through this: local copies already drifted apart
/// in sizes (22 vs 28) and borders — hence "two different tab sizes".
struct SettingChip<Content: View>: View {
    let active: Bool
    /// A choice that exists but cannot be made here — an upscale the source has
    /// no pixels for, say. It stays in its place, dimmed: a row of chips that
    /// appears and disappears as the neighbouring choice changes is worse than
    /// one with a greyed-out member (Anton, 2026-08-04).
    var enabled = true
    let action: () -> Void
    private let content: Content

    init(active: Bool, enabled: Bool = true, action: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.active = active
        self.enabled = enabled
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(
                    active ? Theme.chipBg : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(active ? Theme.controlStroke : Theme.divider, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .hoverDim()
    }
}

extension SettingChip where Content == Text {
    /// Text chip — the base case.
    init(_ label: String, active: Bool, enabled: Bool = true, action: @escaping () -> Void) {
        self.init(active: active, enabled: enabled, action: action) {
            Text(label).font(Theme.mono(10))
        }
    }
}

/// Lid glyph (laptop side view, closing arc arrow) as an image for
/// documentation texts: docs must show OUR glyph, not the system
/// laptop. Geometry mirrors the panel's lidGlyph (open state).
@MainActor
enum LidDocIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(color: NSColor) -> NSImage {
        let key = color.description
        if let hit = cache[key] { return hit }
        let size = NSSize(width: 20, height: 14)
        let img = NSImage(size: size, flipped: true) { rect in
            let w = rect.width
            let h = rect.height
            let baseY = h * 0.82
            color.setStroke()

            let base = NSBezierPath()
            base.lineWidth = 1.4
            base.lineCapStyle = .round
            let hinge = NSPoint(x: w * 0.24, y: baseY)
            base.move(to: hinge)
            base.line(to: NSPoint(x: w - 1.5, y: baseY))
            base.stroke()

            let screenLength = baseY - 1.5
            let top = NSPoint(x: hinge.x - screenLength * 0.31,
                              y: hinge.y - screenLength * 0.95)
            let screen = NSBezierPath()
            screen.lineWidth = 1.4
            screen.lineCapStyle = .round
            screen.move(to: hinge)
            screen.line(to: top)
            screen.stroke()

            // closing arc: a quadratic curve as an exact cubic
            let arcStart = NSPoint(x: w * 0.38, y: h * 0.18)
            let arcEnd = NSPoint(x: w * 0.76, y: h * 0.60)
            let control = NSPoint(x: w * 0.82, y: h * 0.16)
            let c1 = NSPoint(x: arcStart.x + (control.x - arcStart.x) * 2 / 3,
                             y: arcStart.y + (control.y - arcStart.y) * 2 / 3)
            let c2 = NSPoint(x: arcEnd.x + (control.x - arcEnd.x) * 2 / 3,
                             y: arcEnd.y + (control.y - arcEnd.y) * 2 / 3)
            let arc = NSBezierPath()
            arc.lineWidth = 1.1
            arc.lineCapStyle = .round
            arc.move(to: arcStart)
            arc.curve(to: arcEnd, controlPoint1: c1, controlPoint2: c2)
            arc.stroke()

            let head = NSBezierPath()
            head.lineWidth = 1.1
            head.lineCapStyle = .round
            head.lineJoinStyle = .round
            head.move(to: NSPoint(x: arcEnd.x - 2.6, y: arcEnd.y - 2.4))
            head.line(to: arcEnd)
            head.line(to: NSPoint(x: arcEnd.x + 2.6, y: arcEnd.y - 2.4))
            head.stroke()
            return true
        }
        cache[key] = img
        return img
    }
}

/// Formatted documentation: paragraphs, bullets with an accent marker,
/// "term — description" highlighted in bold. Works on top of finished translations.
struct DocView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { index, paragraph in
                let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                // A release heading ("1.2.0 — date") opens a new block: give it
                // extra air above so versions read as sections, not as one more
                // bullet in the previous release's list.
                paragraphView(trimmed)
                    .padding(.top, index > 0 && isVersionHeading(trimmed) ? 10 : 0)
            }
        }
    }

    private func isVersionHeading(_ paragraph: String) -> Bool {
        paragraph.range(of: #"^\d+\.\d+(\.\d+)? — "#, options: .regularExpression) != nil
    }

    @ViewBuilder
    private func paragraphView(_ paragraph: String) -> some View {
        let isBullet = paragraph.hasPrefix("• ")
        let content = isBullet ? String(paragraph.dropFirst(2)) : paragraph
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if isBullet {
                Text("•")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.editing)
            }
            styledText(content)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func styledText(_ content: String) -> Text {
        // "term — description": the term goes bold if the dash is near the start.
        // Distance is measured without icon tokens — {sym:...} are long,
        // but on screen they are a single glyph
        if let range = content.range(of: " — "),
           visibleLength(String(content[..<range.lowerBound])) <= 30 {
            let term = String(content[..<range.lowerBound])
            let rest = String(content[range.upperBound...])
            return rich(term, font: Theme.mono(12, weight: .bold), color: Theme.textPrimary)
                + Text(" — ")
                .font(Theme.mono(12))
                .foregroundColor(Theme.textTertiary)
                + rich(rest, font: Theme.mono(12), color: Theme.docText)
        }
        return rich(content, font: Theme.mono(12), color: Theme.docText)
    }

    /// String length as a human would see it: icon tokens = 1 character.
    private func visibleLength(_ string: String) -> Int {
        string.replacingOccurrences(
            of: #"\{sym:[a-zA-Z0-9.]+\}"#, with: "•", options: .regularExpression
        ).count
    }

    /// Text with inline icons: a {sym:name} token in a translation string
    /// turns into an SF Symbol of the same font and color.
    private func rich(_ string: String, font: Font, color: Color) -> Text {
        var result = Text(verbatim: "")
        var rest = Substring(string)
        while let open = rest.range(of: "{sym:") {
            result = result + Text(String(rest[..<open.lowerBound])).font(font).foregroundColor(color)
            guard let close = rest[open.upperBound...].firstIndex(of: "}") else {
                // unclosed token — show as is, don't lose the text
                result = result + Text(String(rest[open.lowerBound...])).font(font).foregroundColor(color)
                return result
            }
            let name = String(rest[open.upperBound..<close])
            if name == "lid" {
                // our own lid glyph — it has no SF Symbol equivalent
                result = result + Text(Image(nsImage: LidDocIcon.image(color: NSColor(color))))
                    .font(font).foregroundColor(color)
            } else if !name.isEmpty,
               NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                result = result + Text(Image(systemName: name)).font(font).foregroundColor(color)
            }
            rest = rest[rest.index(after: close)...]
        }
        result = result + Text(String(rest)).font(font).foregroundColor(color)
        return result
    }
}

/// "Let Hop open these files" — the one shape both offers use (torrent files and
/// archives). It shows the LIVE Launch Services state rather than a stored flag:
/// the default can be changed in Finder at any moment, and a control that
/// disagrees with the system is worse than no control (Anton, 2026-07-26). The
/// state is re-read whenever Hop becomes active again, which is exactly when a
/// user comes back from changing it elsewhere.
struct DefaultHandlerCard: View {
    let label: String
    /// Reads Launch Services; called on appear and on every app activation.
    let isDefault: () -> Bool
    /// Claims the types Hop is allowed to claim.
    let claim: () async -> Void
    /// Shown instead of the label once Hop holds them.
    let doneLabel: String

    @State private var held = false
    @State private var changing = false

    var body: some View {
        Button {
            changing = true
            Task {
                await claim()
                held = isDefault()
                changing = false
            }
        } label: {
            HStack {
                // The LABEL never changes places with the state: two of these
                // cards sit in the same settings screen, and they have to read
                // as one control in two states, not as two controls (Anton,
                // 2026-07-26). The seal carries the state — outline to offer,
                // filled green once Hop holds the types.
                Text(label)
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(held ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if changing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: held ? "checkmark.seal.fill" : "checkmark.seal")
                        .font(.system(size: 11))
                        .foregroundStyle(held ? Theme.accentGreen : Theme.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .hoverHighlight(7)
        .disabled(held || changing)
        .help(held ? doneLabel : label)
        .onAppear { held = isDefault() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            held = isDefault()
        }
    }
}

/// A module's own mark at the head of its row. The frame is FIXED because SF
/// Symbols differ in height as well as width: `doc.zipper` is a tall document
/// and `archivebox` a squat box, so at the same point size the converter card
/// came out 1.5pt taller than the archive one right next to it (Anton,
/// 2026-07-26). Colour stays with the caller — a module marks its own state.
struct ModuleMarkIcon: View {
    let symbol: String
    var color: Color = Theme.textSecondary

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12))
            .foregroundStyle(color)
            .frame(width: 16, height: 14)
    }
}

/// The icon of a module row's action — the one place their size and weight are
/// decided. SF Symbols are not drawn to a common optical size: at the same point
/// size a dashed viewfinder looks visibly smaller than a boxed arrow, and the
/// eyedropper looks heavier than both, so the row read as a set of mismatched
/// buttons (Anton, 2026-07-26). The table below trims each glyph to the same
/// visual height; everything else stays identical — regular weight, secondary
/// colour, one tap area.
struct RowActionIcon: View {
    let symbol: String
    /// The action is running right now (the eyedropper while the loupe is up).
    var active = false
    /// The WHOLE row is the button (converter, archives), so the glyph needs no
    /// tap area of its own — and a 22pt one would make those cards taller than
    /// every other row in the panel (Anton, 2026-07-26).
    var compact = false

    /// Point size per symbol, chosen so the glyphs match on screen rather than
    /// on paper. A symbol that is not listed gets the plain row size.
    private static let opticalSize: [String: CGFloat] = [
        // a marquee, the shape the user drags on screen. Matching HEIGHT is not
        // enough for a shape this different: a landscape marquee tall enough to
        // match the arrow ran half again as wide, and width is what reads as
        // "bigger". The square one at this size draws 11.3 x 12.0 — the arrow's
        // own box to a fraction of a point (Anton, 2026-07-27).
        "square.dashed": 12.5,
        "arrow.up.forward.app": 12.5,   // boxed, fills its frame
        "eyedropper": 12,               // tall and heavy
    ]

    /// The eyedropper is a SOLID shape while its neighbours are outlines, so at
    /// the same weight it reads as a much darker button. A lighter stroke puts
    /// the same amount of ink on screen.
    private static let opticalWeight: [String: Font.Weight] = [
        "eyedropper": .light,
    ]

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: Self.opticalSize[symbol] ?? 13,
                          weight: Self.opticalWeight[symbol] ?? .regular))
            .foregroundStyle(active ? Theme.editing : Theme.textSecondary)
            .frame(width: compact ? 16 : 24, height: compact ? 14 : 22)
            .contentShape(Rectangle())
    }
}

/// Text label button: color becomes primary on hover,
/// no background fill (presets, cycle templates).
struct HoverLabel: View {
    let text: String
    var size: CGFloat = 11
    var weight: Font.Weight = .medium
    var color: Color = Theme.textTertiary
    var minWidth: CGFloat? = nil
    @State private var hovering = false

    var body: some View {
        Text(text)
            .font(Theme.mono(size, weight: weight))
            .foregroundStyle(hovering ? Theme.textPrimary : color)
            .frame(minWidth: minWidth)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct SectionChips: View {
    let items: [(raw: String, label: String)]
    @Binding var selection: String

    /// Minimum row width: all chips match the widest label
    /// plus side padding — no language runs into the edge.
    static func requiredWidth(for labels: [String]) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        let widest = labels
            .map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
        let chip = widest + 24
        let count = CGFloat(labels.count)
        return count * chip + (count - 1) * 4
    }

    /// true — chips take their natural width and wrap onto new lines
    /// when they don't fit (the about window at any width).
    var wraps = false

    var body: some View {
        if wraps {
            FlowLayout(spacing: 4) {
                ForEach(items, id: \.raw) { chip($0, natural: true) }
            }
        } else {
            HStack(spacing: 4) {
                ForEach(items, id: \.raw) { chip($0, natural: false) }
            }
        }
    }

    @ViewBuilder
    private func chip(_ item: (raw: String, label: String), natural: Bool) -> some View {
        let active = selection == item.raw
        Button {
            selection = item.raw
        } label: {
            Text(item.label)
                .font(Theme.mono(11.5, weight: .semibold))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, natural ? 10 : 6)
                .frame(maxWidth: natural ? nil : .infinity)
                .padding(.vertical, 8)
                .background(
                    active ? Theme.chipBg : Theme.fieldBg,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(active ? Theme.controlStroke : .clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(5)
    }
}

/// Flow layout: elements keep their own width; if one doesn't fit — new line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Soft pulsing of the outline — hints that the timer is alive
/// and pause is clickable.
struct PulsingRing: View {
    var body: some View {
        // no repeatForever: an infinite animation made NSHostingController
        // constantly recalculate its size — the popover trembled
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let bright = Int(context.date.timeIntervalSinceReferenceDate) % 2 == 0
            Circle()
                .stroke(Theme.controlStroke, lineWidth: 1.5)
                .opacity(bright ? 1 : 0.35)
                .animation(.easeInOut(duration: 1.0), value: bright)
        }
    }
}

/// Mini chart: one or more lines on a shared strip,
/// each series normalized to its own range.
struct Sparkline: View {
    let series: [(values: [Double], color: Color)]

    var body: some View {
        Canvas { ctx, size in
            for line in series {
                let values = line.values
                guard values.count > 1 else { continue }
                let low = values.min() ?? 0
                let high = values.max() ?? 1
                let span = max(high - low, 0.0001)
                var path = Path()
                for (index, value) in values.enumerated() {
                    let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                    let y = size.height * (1 - CGFloat((value - low) / span)) * 0.9 + size.height * 0.05
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                ctx.stroke(path, with: .color(line.color.opacity(0.85)), lineWidth: 1)
            }
        }
        .frame(height: 16)
    }
}

// MARK: - Inline-field and row affordances (shared by tracker + to-dos)

/// A glyph-only button that brightens tertiary → primary on hover, the
/// icon counterpart of `HoverLabel`. Used for the commit/cancel controls on
/// inline edit fields.
struct HoverIconButton: View {
    let symbol: String
    let action: () -> Void
    var size: CGFloat = 10
    /// What the icon does, on hover. Icon-only controls are unreadable without
    /// it, so it is a parameter of the shared component rather than something
    /// each call site remembers (Anton, 2026-07-30).
    var help: String?
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textTertiary)
                // 18pt — the floor for a comfortable hit target; sized so the
                // tracker's inline-edit fields (nameField/totalField) fit the
                // task row's untouched 22pt content budget without growing it
                // (see the row-height comment on TrackerView's taskRow).
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .helpIfAny(help)
    }
}

/// The commit/cancel pair shown right of an inline edit field: `checkmark`
/// commits, `xmark` cancels. Return/Escape keep working independently; this is
/// the mouse-only equivalent so a field can be finished without the keyboard.
struct FieldCommitButtons: View {
    let onCommit: () -> Void
    let onCancel: () -> Void
    var lang: AppLanguage = L10n.current

    var body: some View {
        HStack(spacing: 2) {
            HoverIconButton(symbol: "checkmark", action: onCommit,
                            help: L10n.t(.fieldCommit, lang))
            HoverIconButton(symbol: "xmark", action: onCancel,
                            help: L10n.t(.quitCancel, lang))
        }
    }
}

/// Hover-only row delete. The row modules insert it IN FLOW — never as an
/// overlay — only while the row is hovered, so a non-hovered row reserves no
/// width and the row's trailing content (the tracker's time; nothing follows
/// it in to-dos) never moves and is never covered. Its own 22×22 hit area sits
/// entirely inside the row's flexible spacer gap, with the row's normal 6pt
/// HStack spacing separating it from its neighbors on both sides, so it can
/// never intercept a click meant for the time label beside it.
struct HoverDeleteX: View {
    let action: () -> Void
    var help: String?
    /// The button's box. 22pt matches a task row, whose leading circle already
    /// makes the row that tall; a shorter row (a line of a task's history) asks
    /// for a smaller one, or the ✕ would push the row taller the moment the
    /// pointer arrives (Anton, 2026-08-28).
    var size: CGFloat = 22

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: size, height: size)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(4)
        .helpIfAny(help)
    }
}

/// The in-row delete confirmation shared by the tracker and to-do rows. It is
/// swapped in for the hover ✕ that opened it, while the row's leading circle and
/// name — and, in the tracker, the far-right time — stay exactly where they are,
/// so the row keeps its silhouette and height and only the ✕ region changes.
/// `delete` (destructive `Theme.accentRed`, the torrent confirm's token) sits on
/// the LEFT; `cancel` (tertiary) is this component's RIGHTMOST element and takes
/// the ✕'s EXACT slot — flush-right in to-dos (where the ✕ was rightmost), or
/// immediately left of the tracker's inert time (where the ✕ was), so a reflexive
/// repeat click at the same spot cancels instead of deleting, with a clear 12pt
/// gap between the two options. Escape cancels via `.cancelAction` (same
/// mechanism as the tab-delete confirm). No question line: the two labelled
/// buttons in the row are the whole prompt.
struct RowDeleteConfirm: View {
    let lang: AppLanguage
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDelete) {
                HoverLabel(text: L10n.t(.trackerDelete, lang), size: 10, color: Theme.accentRed)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.trackerDelete, lang))
            Button(action: onCancel) {
                HoverLabel(text: L10n.t(.quitCancel, lang), size: 10, color: Theme.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(L10n.t(.quitCancel, lang))
        }
    }
}

/// Shared geometry for the leading circle of the row modules (the tracker's
/// play/stop button and the to-do checkbox), so the two read as ONE control at
/// ONE size on the shared left column. The visible circle is `diameter`; both
/// modules LEFT-ALIGN it (not center it) in a `gutter`-wide leading slot, so its
/// visible edge sits exactly on the row's 2pt inset — the same line the module
/// subheader and the "+ new task" footer text start on, edge to edge, no gap.
/// This keeps the left edge and the gap-to-text identical between the two
/// modules, and leaves the tracker's long-run row inset (2 + gutter + 6 = 30pt,
/// which targets the task text past the circle, not the circle itself) unchanged.
enum RowCircle {
    static let diameter: CGFloat = 18   // between the old transport 22 and checkbox ~13
    /// The to-do checkbox is a RING, and a ring reads bigger than a disc of the
    /// same size — next to the tracker's filled play button it looked like a
    /// different control (Anton, 2026-07-28). 16pt is the optical match.
    static let checkboxDiameter: CGFloat = 16
    static let gutter: CGFloat = 22
    static let glyphSize: CGFloat = 9
    static let strokeWidth: CGFloat = 1.5
}

/// A play triangle drawn as a closed path rather than the SF glyph — lets the
/// corners come out rounded (see `PlayGlyph` below). `inset` is baked into the
/// path itself (not `.padding`) so a caller can size the stroke and the path
/// off the same box.
private struct PlayTriangleShape: Shape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        path.closeSubpath()
        return path
    }
}

/// The house rounded-corner play triangle — the ONE play glyph across the app
/// (the tracker/to-do transport, the main timer button, the torrent row control).
/// SF's `play.fill` is sharp-cornered; `MenuBarIcon.drawBadge`'s hand-drawn
/// running badge already solved this for the status-bar dot (fill the path, then
/// stroke it with a round join thick enough to bulge the corners smooth) — this
/// reproduces the same technique in SwiftUI. Everything scales off `box`, so one
/// `round` factor serves every size; pause glyphs keep SF's `pause.fill`.
struct PlayGlyph: View {
    let color: Color
    var box: CGFloat
    /// Corner rounding, as a fraction of `box`: it sets the round-join stroke
    /// width, so a bigger fraction bulges the corners rounder. Tuned noticeably
    /// higher than the original 0.34 (Anton: "round as much as possible") while
    /// the shape still reads as a play triangle down to the 18pt row circle.
    var round: CGFloat = 0.46

    var body: some View {
        // The path sits inset by half the stroke width, so the stroke's
        // outward bulge fills back out to `box` — same footprint as an
        // un-inset sharp triangle would have, just with rounded corners.
        let strokeWidth = box * round
        let inset = strokeWidth / 2
        ZStack {
            PlayTriangleShape(inset: inset).fill(color)
            PlayTriangleShape(inset: inset)
                .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineJoin: .round))
        }
        .frame(width: box, height: box)
        // Optical centering: the triangle's mass sits toward its flat left
        // edge (the point only reaches the box's right edge at one pixel),
        // so a geometrically centered triangle reads left-heavy — nudge right.
        .offset(x: box * 0.06)
    }
}

/// A five-pointed star as a closed path, so its points can be rounded the way
/// the play triangle's corners are. SF's `star.fill` comes out needle-sharp next
/// to the house glyphs (Anton, 2026-07-28).
private struct StarShape: Shape {
    var inset: CGFloat = 0
    /// Corner rounding as a fraction of the box. The rounded outline is baked
    /// into the PATH (stroke it, then union with itself), so the shape can be
    /// filled once — filling and stroking separately made a translucent colour
    /// pile up along the rim and read as a glow (Anton, 2026-07-28).
    var round: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let star = points(in: rect)
        guard round > 0 else { return star }
        let width = min(rect.width, rect.height) * round
        return star.union(star.strokedPath(
            StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)))
    }

    private func points(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: inset, dy: inset)
        let center = CGPoint(x: box.midX, y: box.midY)
        let outer = min(box.width, box.height) / 2
        let inner = outer * 0.42
        var path = Path()
        for step in 0..<10 {
            let radius = step.isMultiple(of: 2) ? outer : inner
            // start at the top point and walk clockwise
            let angle = -.pi / 2 + CGFloat(step) * .pi / 5
            let point = CGPoint(x: center.x + cos(angle) * radius,
                                y: center.y + sin(angle) * radius)
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

/// The house star: filled or outlined, with rounded points. Same technique as
/// `PlayGlyph` — fill the path, then stroke it with a round join thick enough to
/// bulge the corners smooth.
struct StarGlyph: View {
    let color: Color
    var box: CGFloat
    var filled: Bool = true
    /// Point rounding as a fraction of `box`. Kept lower than the play glyph's:
    /// a star has ten corners, and rounding them as hard would turn it into a
    /// flower.
    var round: CGFloat = 0.16

    var body: some View {
        let shape = StarShape(inset: box * round / 2, round: round)
        Group {
            // Filled = a flat solid shape, nothing on top of it. Outlined = the
            // same rounded silhouette drawn as a thin line.
            if filled {
                shape.fill(color)
            } else {
                shape.stroke(color, style: StrokeStyle(lineWidth: max(1.1, box * 0.09),
                                                       lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: box, height: box)
    }
}

/// The panel's play/pause transport look, shared so the tracker's play/stop
/// button AND the to-do checkbox belong to one family at one `RowCircle.diameter`:
/// a circle that is FILLED (a solid disc, glyph knocked out in `glyphColor`) or
/// BORDERED (a ring in `strokeColor`, glyph — if any — in `glyphColor`). An empty
/// `systemName` draws no glyph (an unchecked box). Colors default to the timer
/// transport palette; the checkbox passes its own muted tokens. The "start"
/// glyph is our own rounded-corner triangle (`PlayGlyph`), not SF's
/// `play.fill` — pause keeps the SF `pause.fill` bars, whose caps are already
/// rounded via `.semibold`'s corner treatment.
struct TransportCircle: View {
    let systemName: String   // "play.fill" (start) / "pause.fill" (running) / "" (empty ring)
    let filled: Bool         // true = solid disc, false = ring
    var diameter: CGFloat = RowCircle.diameter
    var iconSize: CGFloat = RowCircle.glyphSize
    var fillColor: Color = Theme.playBg
    var strokeColor: Color = Theme.controlStroke
    var glyphColor: Color? = nil   // nil = playFg when filled, textPrimary when bordered

    var body: some View {
        let glyph = glyphColor ?? (filled ? Theme.playFg : Theme.textPrimary)
        Group {
            if systemName == "play.fill" {
                // Bigger than the 0.315 it shrank to, and LESS rounded with it
                // (Anton, 2026-08-28): at 0.46 the round join eats the tip and
                // the top and bottom corners, so growing the box only looked
                // like growing the width. A tighter join keeps the height the
                // growth was meant to buy.
                PlayGlyph(color: glyph, box: diameter * 0.38, round: 0.36)
            } else if systemName.isEmpty {
                Color.clear
            } else {
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(glyph)
            }
        }
        .frame(width: diameter, height: diameter)
        .background(filled ? fillColor : .clear, in: Circle())
        .overlay {
            // strokeBorder, not stroke: a centred stroke straddles the path and
            // grows the circle by its own width, which is half of why the ring
            // outsized the disc.
            if !filled { Circle().strokeBorder(strokeColor, lineWidth: RowCircle.strokeWidth) }
        }
        .contentShape(Circle())
    }
}

/// A tiny diagram of what happens to a picture that is not the frame's shape:
/// cropped to fill it, fitted whole with empty bars, or fitted over a blurred
/// copy of itself. Three words are three guesses until you see them (Anton,
/// 2026-08-28); this draws the answer beside the row.
struct FitGlyph: View {
    /// "fill" | "pad" | "blur" — the stored `convVideoFit` values.
    let fit: String
    var height: CGFloat = 13

    private var width: CGFloat { height * 1.6 }

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: 2)
        ZStack {
            switch fit {
            case "pad":
                // the picture whole, letterboxed: bars above and below stay empty
                frame.stroke(Theme.textTertiary, lineWidth: 1)
                Rectangle()
                    .fill(Theme.textSecondary)
                    .frame(width: width - 2, height: height * 0.5)
            case "blur":
                // the same fit, but the bars carry a soft copy of the picture
                frame.fill(Theme.textTertiary.opacity(0.45))
                frame.stroke(Theme.textTertiary, lineWidth: 1)
                Rectangle()
                    .fill(Theme.textSecondary)
                    .frame(width: width - 2, height: height * 0.5)
            default:
                // filled edge to edge, with what does not fit hanging outside
                frame.stroke(Theme.textTertiary, lineWidth: 1)
                Rectangle()
                    .fill(Theme.textSecondary)
                    .frame(width: width + 6, height: height - 2)
                    .clipShape(frame)
                Rectangle()
                    .fill(Theme.textTertiary.opacity(0.5))
                    .frame(width: width + 6, height: height - 2)
                    .mask(
                        HStack(spacing: width - 6) {
                            Rectangle().frame(width: 3)
                            Rectangle().frame(width: 3)
                        }
                    )
            }
        }
        .frame(width: width, height: height)
    }
}
