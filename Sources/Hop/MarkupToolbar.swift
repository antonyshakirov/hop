import AppKit
import HopCore
import SwiftUI

/// The floating panel both markup modules carry.
///
/// It is dragged by anything that is not a button, snaps to the nearest screen
/// edge and turns with it: horizontal at the top and bottom, vertical at the
/// sides. Colour and width live in a popover, so the panel stays a row of
/// tools.
struct MarkupToolbar: View {
    enum Edge: String {
        case top, bottom, leading, trailing

        var isVertical: Bool { self == .leading || self == .trailing }
    }

    @ObservedObject var surface: MarkupSurface
    let tools: [MarkupTool]
    @Binding var edge: Edge
    var lang: AppLanguage
    /// False while the surface is handing clicks to whatever is underneath: no
    /// tool is in hand, so none is shown as chosen.
    var toolsActive = true
    var trailing: AnyView?
    var leading: AnyView?

    @State private var showingColour = false
    @State private var showingWidth = false
    @State private var options: MarkupTool?
    @State private var hovered: MarkupTool?

    var body: some View {
        Group {
            if edge.isVertical {
                VStack(spacing: 4) { content }
            } else {
                HStack(spacing: 4) { content }
            }
        }
        .padding(edge.isVertical ? EdgeInsets(top: 8, leading: 7, bottom: 8, trailing: 7)
                                 : EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.isDark ? Color(white: 0.086) : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.controlStroke.opacity(0.6)))
                .shadow(color: .black.opacity(Theme.isDark ? 0.6 : 0.16), radius: 14, y: 6)
        )
        .onHover { surface.pointerOverPanel = $0 }

    }

    @ViewBuilder
    private var content: some View {
        MarkupIcon(glyph: .grip, size: 16)
            .foregroundStyle(Theme.textTertiary)
            .rotationEffect(.degrees(edge.isVertical ? 90 : 0))

        if let leading {
            leading
            divider
        }

        ForEach(tools, id: \.self) { tool in
            button(for: tool)
        }

        divider

        Button {
            showingWidth.toggle()
        } label: {
            MarkupIcon(glyph: .weight)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.t(.mkWidth, lang))
        .popover(isPresented: $showingWidth, arrowEdge: popoverEdge) {
            MarkupWidthPopover(surface: surface, lang: lang)
        }

        Button {
            showingColour.toggle()
        } label: {
            Circle()
                .fill(Color(markupHex: surface.ink(for: surface.tool).hex))
                .frame(width: 17, height: 17)
                .overlay(Circle().strokeBorder(Theme.glyphInk.opacity(0.35), lineWidth: 1.5))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingColour, arrowEdge: popoverEdge) {
            MarkupColourPopover(surface: surface)
        }

        if let trailing {
            divider
            trailing
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: edge.isVertical ? 20 : 1, height: edge.isVertical ? 1 : 20)
    }

    private var popoverEdge: SwiftUI.Edge { edge == .top ? .bottom : .top }

    /// Pressing a tool that is already in hand opens what it can be set to, and
    /// closes it again. Only the tools that HAVE settings carry a popover: one
    /// on every button broke clicks through the drawing layer's panel.
    @ViewBuilder
    private func button(for tool: MarkupTool) -> some View {
        if settable(tool) {
            plainButton(for: tool)
                .popover(isPresented: Binding(
                    get: { options == tool },
                    set: { if !$0 { options = nil } }
                ), arrowEdge: popoverEdge) {
                    settings(for: tool)
                }
        } else {
            plainButton(for: tool)
        }
    }

    private func plainButton(for tool: MarkupTool) -> some View {
        let chosen = toolsActive && surface.tool == tool
        return Button {
            if settable(tool), chosen {
                options = options == tool ? nil : tool
            } else {
                surface.tool = tool
                options = nil
            }
        } label: {
            MarkupIcon(glyph: MarkupToolbar.glyph(for: tool))
                .foregroundStyle(chosen ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(chosen ? Theme.chipBg : (hovered == tool ? Theme.hoverBg : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? tool : (hovered == tool ? nil : hovered) }
        .help("\(L10n.t(MarkupToolbar.name(of: tool), lang)) · \(MarkupToolbar.letter(of: tool))")
    }

    /// Which tools have something to set. The select tool has whatever the mark
    /// in hand has: pressing it again opens THAT mark's settings, so a blur is
    /// tuned on the blur that is already on the picture.
    private func settable(_ tool: MarkupTool) -> Bool {
        switch tool {
        case .arrow, .text, .blur: return true
        case .select: return surface.selected != nil
        default: return false
        }
    }

    @ViewBuilder
    private func settings(for tool: MarkupTool) -> some View {
        switch tool == .select ? (surface.selected?.tool ?? .select) : tool {
        case .arrow: MarkupArrowPopover(surface: surface)
        case .text: MarkupTextPopover(surface: surface, lang: lang)
        case .blur: MarkupBlurPopover(surface: surface, lang: lang)
        default: MarkupColourPopover(surface: surface)
        }
    }

    static func glyph(for tool: MarkupTool) -> MarkupGlyph {
        switch tool {
        case .select: return .cursor
        case .pencil: return .pencil
        case .fadingInk: return .fadingInk
        case .marker: return .marker
        case .arrow: return .arrow
        case .line: return .line
        case .rectangle: return .rectangle
        case .oval: return .oval
        case .steps: return .steps
        case .text: return .text
        case .magnifier: return .magnifier
        case .blur: return .blur
        case .eraser: return .eraser
        case .crop: return .crop
        }
    }

    static func name(of tool: MarkupTool) -> L10nKey {
        switch tool {
        case .select: return .mkSelect
        case .pencil: return .mkPencil
        case .fadingInk: return .mkFading
        case .marker: return .mkMarker
        case .arrow: return .mkArrow
        case .line: return .mkLine
        case .rectangle: return .mkRect
        case .oval: return .mkOval
        case .steps: return .mkSteps
        case .text: return .mkText
        case .magnifier: return .mkMagnifier
        case .blur: return .mkBlur
        case .eraser: return .mkEraser
        case .crop: return .mkCrop
        }
    }

    /// The letter printed in the tooltip and accepted as a shortcut while a
    /// markup surface has the keyboard.
    static func letter(of tool: MarkupTool) -> String {
        switch tool {
        case .select: return "v"
        case .pencil: return "p"
        case .fadingInk: return "f"
        case .marker: return "m"
        case .arrow: return "a"
        case .line: return "l"
        case .rectangle: return "r"
        case .oval: return "o"
        case .steps: return "n"
        case .text: return "t"
        case .magnifier: return "z"
        case .blur: return "b"
        case .eraser: return "e"
        case .crop: return "c"
        }
    }

    static func tool(forLetter letter: String) -> MarkupTool? {
        MarkupTool.allCases.first { self.letter(of: $0) == letter.lowercased() }
    }

    /// The letter a key PRINTS depends on the layout, and on a non-Latin one
    /// every shortcut here was dead. The physical key does not move.
    static func letter(forKeyCode code: UInt16) -> String? {
        Self.ansi[code]
    }

    static let zKeyCode: UInt16 = 6

    private static let ansi: [UInt16: String] = [
        0: "a", 3: "f", 6: "z", 8: "c", 9: "v", 11: "b", 14: "e", 15: "r",
        17: "t", 31: "o", 35: "p", 37: "l", 45: "n", 46: "m",
    ]
}

/// The colour of the tool in hand: eight to press, and the system picker for
/// anything else. Each tool keeps its own.
struct MarkupColourPopover: View {
    @ObservedObject var surface: MarkupSurface

    @State private var mixed: [String] = MarkupSettings.recentColours()

    private let palette = ["#FF453A", "#FF9F0A", "#FFD60A", "#32D74B",
                           "#0A84FF", "#BF5AF2", "#FFFFFF", "#1C1C1E"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(palette, id: \.self) { hex in
                    swatch(hex)
                }
            }

            HStack(spacing: 8) {
                ForEach(mixed, id: \.self) { hex in
                    swatch(hex)
                }
                if !mixed.isEmpty {
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 22)
                }
                Button {
                    MarkupColourPanel.shared.show(startingAt: current.hex, onPick: { picked in
                        write { $0.hex = picked.markupHex }
                    }, onSettled: {
                        mixed = MarkupSettings.recentColours()
                    })
                } label: {
                    Circle()
                        .fill(AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Theme.glyphInk.opacity(0.2), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(Theme.background)
    }

    private func swatch(_ hex: String) -> some View {
        Button {
            write { $0.hex = hex }
        } label: {
            Circle()
                .fill(Color(markupHex: hex))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().strokeBorder(
                        Theme.glyphInk.opacity(current.hex == hex ? 0.9 : 0.2),
                        lineWidth: current.hex == hex ? 2 : 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var current: MarkupInk { surface.ink(for: surface.tool) }

    private func write(_ change: (inout MarkupInk) -> Void) {
        var ink = current
        change(&ink)
        surface.setInk(ink, for: surface.tool)
    }
}

/// How thick the tool in hand draws. Its own control: the width belongs to
/// every tool, and burying it under the colour hid it.
struct MarkupWidthPopover: View {
    @ObservedObject var surface: MarkupSurface
    var lang: AppLanguage

    private let presets: [Double] = [2, 4, 9, 18]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t(.mkWidth, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("\(Int(current.width.rounded()))")
                    .font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
            }

            // A slider as well as the four: a tool whose width is not one of
            // them showed nothing chosen at all, which read as no width set.
            Slider(value: Binding(
                get: { current.width },
                set: { value in write { $0.width = value.rounded() } }
            ), in: 1...30)

            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { width in
                    Button {
                        write { $0.width = width }
                    } label: {
                        Circle()
                            .fill(Theme.glyphInk.opacity(current.width == width ? 0.92 : 0.5))
                            .frame(width: width / 2 + 3, height: width / 2 + 3)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(current.width == width ? Theme.chipBg : .clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 210)
        .background(Theme.background)
    }

    private var current: MarkupInk { surface.ink(for: surface.tool) }

    private func write(_ change: (inout MarkupInk) -> Void) {
        var ink = current
        change(&ink)
        surface.setInk(ink, for: surface.tool)
    }
}

/// Three sizes of type. Not a font panel: a screenshot wants a caption fast.
struct MarkupTextPopover: View {
    @ObservedObject var surface: MarkupSurface
    var lang: AppLanguage

    private let sizes: [(Double, CGFloat)] = [(14, 11), (24, 15), (40, 21)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(sizes, id: \.0) { size, shown in
                Button {
                    var ink = surface.ink(for: .text)
                    ink.width = size
                    surface.setInk(ink, for: .text)
                } label: {
                    Text("A")
                        .font(.system(size: shown, weight: .semibold))
                        .foregroundStyle(surface.ink(for: .text).width == size
                                         ? Theme.textPrimary : Theme.textSecondary)
                        .frame(width: 40, height: 34)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(surface.ink(for: .text).width == size ? Theme.chipBg : Theme.rowBg))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.background)
    }
}

/// What the blur does: which side of the frame it works on, what shape the
/// frame is, and how hard.
struct MarkupBlurPopover: View {
    @ObservedObject var surface: MarkupSurface
    var lang: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row([(L10n.t(.blurInside, lang), MarkupBlur.Mode.inside),
                 (L10n.t(.blurAround, lang), .around)],
                current: current.mode) { mode in
                    var next = current; next.mode = mode; surface.blurInHand = next
                }

            row([(L10n.t(.mkRect, lang), MarkupBlur.Shape.rectangle),
                 (L10n.t(.mkOval, lang), .oval),
                 (L10n.t(.shapeLasso, lang), .lasso)],
                current: current.shape) { shape in
                    var next = current; next.shape = shape; surface.blurInHand = next
                }

            row([("blur", MarkupBlur.Style.blur),
                 (L10n.t(.blurPixels, lang), .pixels)],
                current: current.style) { style in
                    var next = current; next.style = style; surface.blurInHand = next
                }

            slider(L10n.t(.blurStrength, lang), value: current.strength, range: 1...10) { value in
                var next = current; next.strength = value; surface.blurInHand = next
            }
            if current.mode == .around {
                slider(L10n.t(.blurDim, lang), value: current.dim, range: 0...10) { value in
                    var next = current; next.dim = value; surface.blurInHand = next
                }
            }
        }
        .padding(12)
        .frame(width: 250)
        .background(Theme.background)
    }

    private var current: MarkupBlur { surface.blurInHand }

    private func row<Value: Equatable>(
        _ items: [(String, Value)], current: Value, pick: @escaping (Value) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                Button { pick(item.1) } label: {
                    Text(item.0)
                        .font(Theme.mono(10))
                        .lineLimit(1)
                        .foregroundStyle(current == item.1 ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(current == item.1 ? Theme.chipBg : Theme.rowBg))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func slider(
        _ title: String, value: Int, range: ClosedRange<Int>, set: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("\(value)").font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
            }
            Slider(value: Binding(get: { Double(value) }, set: { set(Int($0.rounded())) }),
                   in: Double(range.lowerBound)...Double(range.upperBound))
        }
    }
}

/// The four heads the arrow can carry, drawn rather than named.
struct MarkupArrowPopover: View {
    @ObservedObject var surface: MarkupSurface

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ArrowStyle.allCases, id: \.self) { style in
                Button {
                    surface.arrowStyle = style
                } label: {
                    ArrowStylePreview(style: style)
                        .frame(width: 84, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(surface.arrowStyle == style ? Theme.chipBg : Theme.rowBg)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.background)
    }
}

/// Each arrow drawn the way the tool would draw it, so the choice is made on
/// the shape itself rather than on a word for it.
struct ArrowStylePreview: View {
    let style: ArrowStyle

    var body: some View {
        Canvas { context, size in
            let width = 5.0
            let tail = MarkupPoint(x: 12, y: size.height - 12)
            let tip = MarkupPoint(x: size.width - 12, y: 12)
            let stroke = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            let ink = GraphicsContext.Shading.color(Theme.textPrimary)

            let head = MarkupGeometry.arrowHead(from: tail, to: tip, style: style, width: width)
            let barbs = head.map { CGPoint(x: $0.x, y: $0.y) }
            let stop = barbs.count == 3 ? barbs[1] : CGPoint(x: tip.x - 2, y: tip.y + 2)

            var shaft = Path()
            shaft.move(to: CGPoint(x: tail.x, y: tail.y))
            shaft.addLine(to: stop)
            context.stroke(shaft, with: ink, style: stroke)

            if barbs.count == 3 {
                var triangle = Path()
                triangle.move(to: barbs[0])
                triangle.addLine(to: CGPoint(x: tip.x, y: tip.y))
                triangle.addLine(to: barbs[2])
                triangle.addLine(to: barbs[1])
                triangle.closeSubpath()
                context.fill(triangle, with: ink)
            } else if barbs.count == 2 {
                var open = Path()
                for barb in barbs {
                    open.move(to: barb)
                    open.addLine(to: CGPoint(x: tip.x, y: tip.y))
                }
                context.stroke(open, with: ink, style: stroke)
            }
        }
    }
}

/// The toolbar as it actually lives on a surface: floating, dragged by any
/// spot that is not a button, snapping to the nearest edge when released and
/// turning with it.
struct MarkupToolbarLayer: View {
    @ObservedObject var surface: MarkupSurface
    let tools: [MarkupTool]
    @Binding var edge: MarkupToolbar.Edge
    let size: CGSize
    var lang: AppLanguage
    var trailing: AnyView?
    var leading: AnyView?
    /// A panel of its own beside the toolbar, moving and turning with it.
    var companion: AnyView?

    @State private var spot: CGPoint?
    @State private var grabbedAt: CGPoint?
    @State private var span: CGSize = .zero

    var body: some View {
        Group {
            if edge.isVertical {
                VStack(spacing: 8) { panels }
            } else {
                HStack(spacing: 8) { panels }
            }
        }
            .background(
                GeometryReader { box in
                    Color.clear
                        .onAppear { span = box.size }
                        .onChange(of: box.size) { _, fresh in span = fresh }
                }
            )
            // BEFORE .position(): after it the view fills the whole surface,
            // and the gesture with it — every drag anywhere on the picture took
            // the panel for a walk instead of doing what it was aimed at.
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let from = grabbedAt ?? place()
                        grabbedAt = from
                        settle(at: CGPoint(x: from.x + value.translation.width,
                                           y: from.y + value.translation.height))
                    }
                    .onEnded { value in
                        let from = grabbedAt ?? place()
                        settle(at: CGPoint(x: from.x + value.translation.width,
                                           y: from.y + value.translation.height))
                        grabbedAt = nil
                    }
            )
            .position(place())
    }

    private func settle(at point: CGPoint) {
        let held = clamp(point)
        spot = held
        // The edge is no longer where the panel lives, only which way its
        // popovers open. SPEC: docs/spec.md
        let wanted: MarkupToolbar.Edge = held.y < size.height / 2 ? .top : .bottom
        if edge != wanted { edge = wanted }
    }

    @ViewBuilder private var panels: some View {
        MarkupToolbar(surface: surface, tools: tools, edge: $edge, lang: lang,
                      trailing: trailing, leading: leading)
        if let companion {
            companion
                .padding(edge.isVertical ? EdgeInsets(top: 8, leading: 7, bottom: 8, trailing: 7)
                                         : EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.isDark ? Color(white: 0.086) : Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Theme.controlStroke.opacity(0.6)))
                        .shadow(color: .black.opacity(Theme.isDark ? 0.6 : 0.16), radius: 14, y: 6)
                )
        }
    }

    /// The panel stays where it was put, in both directions.
    private func place() -> CGPoint {
        clamp(spot ?? CGPoint(x: size.width / 2,
                              y: edge == .top ? 60 : size.height - 60))
    }

    /// Whole, and off the sides: the panel never hangs over an edge, and a
    /// pointer dragged past the surface leaves it standing at the margin
    /// instead of chasing a place that does not exist.
    private func clamp(_ point: CGPoint) -> CGPoint {
        let margin: CGFloat = 20
        let half = CGSize(width: max(span.width, 40) / 2, height: max(span.height, 24) / 2)
        return CGPoint(x: held(point.x, half: half.width, of: size.width, margin: margin),
                       y: held(point.y, half: half.height, of: size.height, margin: margin))
    }

    private func held(_ value: CGFloat, half: CGFloat, of whole: CGFloat, margin: CGFloat) -> CGFloat {
        let least = margin + half, most = whole - margin - half
        guard least <= most else { return whole / 2 }
        return min(max(value, least), most)
    }
}

/// The tool letters, live while a markup surface is on screen. ⌘Z and ⇧⌘Z stay
/// with the window's own menu handling; these are the bare letters.
struct MarkupKeys: NSViewRepresentable {
    @ObservedObject var surface: MarkupSurface
    let tools: [MarkupTool]

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.pick = { letter in
            guard let tool = MarkupToolbar.tool(forLetter: letter), tools.contains(tool) else { return false }
            surface.tool = tool
            return true
        }
        view.step = { forward in
            if forward { surface.redo() } else { surface.undo() }
        }
        view.drop = { surface.deleteSelection() }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        var pick: ((String) -> Bool)?
        /// ⌘Z and ⇧⌘Z. Hop is an accessory app with no Edit menu, so there is no
        /// key equivalent for them to travel on.
        var step: ((Bool) -> Void)?
        /// Delete on a selected mark. Answers whether there was one.
        var drop: (() -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.window?.isVisible == true,
                      // a field being typed into owns its keys
                      !(self.window?.firstResponder is NSTextView)
                else { return event }

                if event.modifierFlags.contains(.command) {
                    // With several editors open only the one in front may act.
                    guard self.window?.isKeyWindow == true,
                          event.keyCode == MarkupToolbar.zKeyCode
                    else { return event }
                    self.step?(event.modifierFlags.contains(.shift))
                    return nil
                }

                // 51 backspace, 117 forward delete
                if event.keyCode == 51 || event.keyCode == 117,
                   self.window?.isKeyWindow == true, self.drop?() == true {
                    return nil
                }

                guard !event.modifierFlags.contains(.control),
                      !event.modifierFlags.contains(.option),
                      let letter = MarkupToolbar.letter(forKeyCode: event.keyCode),
                      self.pick?(letter) == true else { return event }
                return nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}


/// The system colour picker, opened where it can be seen. Left to itself the
/// panel comes back wherever it was last put — usually the bottom left of the
/// screen, nowhere near the toolbar it was asked from.
@MainActor
final class MarkupColourPanel: NSObject, NSWindowDelegate {
    static let shared = MarkupColourPanel()

    private var onPick: ((Color) -> Void)?
    private var onSettled: (() -> Void)?
    private var settledHex: String?

    func show(startingAt hex: String, onPick: @escaping (Color) -> Void,
              onSettled: (() -> Void)? = nil) {
        self.onPick = onPick
        self.onSettled = onSettled
        settledHex = nil
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        // The wheel, always: it is the one mode with hue, saturation and
        // brightness each on its own control, and the panel otherwise comes
        // back in whatever mode it was last left in — crayons, or a grey ramp.
        panel.mode = .wheel
        panel.color = Self.lit(NSColor(Color(markupHex: hex)))
        panel.setTarget(self)
        panel.setAction(#selector(picked(_:)))
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                                         y: screen.frame.midY - size.height / 2 + 80))
        }
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func picked(_ sender: NSColorPanel) {
        let colour = Color(nsColor: sender.color)
        settledHex = colour.markupHex
        onPick?(colour)
    }

    /// Only the colour the panel was LEFT on is remembered. It fires its action
    /// on every step of a drag across the wheel, so recording each one filled
    /// the row with neighbouring shades of the one colour actually chosen.
    func windowWillClose(_ notification: Notification) {
        if let settledHex { MarkupSettings.remember(colour: settledHex) }
        settledHex = nil
        onSettled?()
        onSettled = nil
    }

    /// A wheel opened on near-black is a black wheel: every colour on it is
    /// drawn at the current brightness. Starting from a dark or washed-out
    /// colour, the hue is kept and the other two are opened up.
    private static func lit(_ colour: NSColor) -> NSColor {
        guard let srgb = colour.usingColorSpace(.sRGB) else { return colour }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard brightness < 0.35 || saturation < 0.15 else { return srgb }
        return NSColor(hue: hue, saturation: max(saturation, 0.85),
                       brightness: 1, alpha: 1)
    }
}
