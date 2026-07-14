import SwiftUI
import UniformTypeIdentifiers

/// Numeric field with free-form input: lets only digits through,
/// clamps to the range on submit/blur.
struct NumericField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var color: Color = Theme.textPrimary

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .font(Theme.mono(11, weight: .semibold))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            // the AppKit field editor lifts the text by ~1.5px on focus —
            // compensate so the digit doesn't hop
            .offset(y: focused ? 1.5 : 0)
            .frame(width: 44, height: 24)
            .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 5))
            .onAppear { text = "\(value)" }
            .onChange(of: text) { _, new in
                let digits = String(new.filter(\.isNumber).prefix(3))
                if digits != new { text = digits }
                if let v = Int(digits), range.contains(v) { value = v }
            }
            .onChange(of: value) { _, v in
                if !focused { text = "\(v)" }
            }
            .onChange(of: focused) { _, isFocused in
                guard !isFocused else { return }
                if let v = Int(text) {
                    value = min(max(v, range.lowerBound), range.upperBound)
                }
                text = "\(value)"
            }
            .onSubmit {
                if let v = Int(text) {
                    value = min(max(v, range.lowerBound), range.upperBound)
                }
                text = "\(value)"
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
                .font(Theme.mono(11))
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
    @State private var hovering = false

    var body: some View {
        Button {
            if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        } label: {
            Text("antonshakirov.com")
                .font(Theme.mono(11))
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

/// Metric chart: a compact line with a scale on the right; below the chart —
/// time at the edges (window start → "now") and a color legend.
/// Both lines are shades of the metric's color.
struct SparklineCard: View {
    struct Series: Identifiable {
        let label: String
        let points: [SystemStatsController.HistoryPoint]
        let color: Color
        let maxValue: Double
        var dashed = false
        var id: String { label }
    }

    let series: [Series]
    let topLabel: String
    let spanText: String
    let nowText: String
    /// Time window: points are placed by their timestamps, not at equal steps —
    /// history accumulates in the background and is shown "as is", without stretching.
    let start: Date
    let end: Date

    /// Uniform geometry for all cards: the chart and the scale column are fixed,
    /// otherwise the wide "4.0 MB/s" label on network made its chart different.
    private static let chartWidth: CGFloat = 176
    private static let chartHeight: CGFloat = 24

    var body: some View {
        // scale to the LEFT of the chart, chart pinned to the right edge — on the same
        // grid as the row values ("100" on the right differed in padding and
        // bloated the row). The legend and time live under the chart at the same width.
        HStack(alignment: .top, spacing: 8) {
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 0) {
                // scale labels are centered on their grid lines,
                // otherwise "100" at the top line reads as a data label
                Text(topLabel)
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .offset(y: -4.5)
                Spacer()
                Text("0")
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.textTertiary)
                    .offset(y: 4.5)
            }
            .frame(height: Self.chartHeight)
            VStack(alignment: .leading, spacing: 3) {
                ZStack {
                    VStack {
                        Rectangle().fill(Theme.divider).frame(height: 1)
                        Spacer()
                        Rectangle().fill(Theme.divider).frame(height: 1)
                    }
                    ForEach(series) { s in
                        LinePath(points: s.points, maxValue: s.maxValue, start: start, end: end)
                            .stroke(s.color, style: StrokeStyle(
                                lineWidth: 1.2,
                                dash: s.dashed ? [3, 2.5] : []
                            ))
                    }
                }
                .frame(width: Self.chartWidth, height: Self.chartHeight)
                HStack {
                    Text("−" + spanText)
                        .font(Theme.mono(8))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Text(nowText)
                        .font(Theme.mono(8))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(width: Self.chartWidth)
                HStack(spacing: 10) {
                    ForEach(series) { s in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(s.color)
                                .frame(width: 5, height: 5)
                            Text(s.label)
                                .font(Theme.mono(9))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
        }
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
    let action: () -> Void
    private let content: Content

    init(active: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.active = active
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
        .hoverDim()
    }
}

extension SettingChip where Content == Text {
    /// Text chip — the base case.
    init(_ label: String, active: Bool, action: @escaping () -> Void) {
        self.init(active: active, action: action) {
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
            ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                paragraphView(paragraph.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
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
