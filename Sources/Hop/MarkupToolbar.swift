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

        /// Standing on end the panel is about 660pt long; below that a side
        /// would cut it off with no way to grab it back.
        static let uprightLength: CGFloat = 700

        /// The edge a panel dropped at this point belongs to; the nearest one
        /// wins, and a tie goes to the horizontal, which fits more tools.
        static func nearest(to point: CGPoint, in size: CGSize) -> Edge {
            var distances: [(Edge, CGFloat)] = [
                (.top, point.y), (.bottom, size.height - point.y),
            ]
            if size.height >= uprightLength {
                distances += [(.leading, point.x), (.trailing, size.width - point.x)]
            }
            return distances.min { $0.1 < $1.1 }?.0 ?? .bottom
        }
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
    @State private var showingArrow = false
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

    private func button(for tool: MarkupTool) -> some View {
        let chosen = toolsActive && surface.tool == tool
        return Button {
            // The arrow's own shapes hang off its icon: pressing the tool a
            // second time opens them, a third closes them again.
            if tool == .arrow, chosen {
                showingArrow.toggle()
            } else {
                surface.tool = tool
                showingArrow = false
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
        .popover(isPresented: Binding(
            get: { showingArrow && tool == .arrow },
            set: { if !$0 { showingArrow = false } }
        ), arrowEdge: popoverEdge) {
            MarkupArrowPopover(surface: surface)
        }
    }

    static func glyph(for tool: MarkupTool) -> MarkupGlyph {
        switch tool {
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
        0: "a", 3: "f", 6: "z", 8: "c", 11: "b", 14: "e", 15: "r",
        17: "t", 31: "o", 35: "p", 37: "l", 45: "n", 46: "m",
    ]
}

/// The colour of the tool in hand: eight to press, and the system picker for
/// anything else. Each tool keeps its own.
struct MarkupColourPopover: View {
    @ObservedObject var surface: MarkupSurface

    private let palette = ["#FF453A", "#FF9F0A", "#FFD60A", "#32D74B",
                           "#0A84FF", "#BF5AF2", "#FFFFFF", "#1C1C1E"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(palette, id: \.self) { hex in
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

            Rectangle().fill(Theme.divider).frame(width: 1, height: 22)

            ColorPicker("", selection: Binding(
                get: { Color(markupHex: current.hex) },
                set: { picked in write { $0.hex = picked.markupHex } }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 24)
        }
        .padding(12)
        .background(Theme.background)
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

    private let widths: [Double] = [2, 4, 9, 18]

    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.t(.mkWidth, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
            ForEach(widths, id: \.self) { width in
                Button {
                    var ink = surface.ink(for: surface.tool)
                    ink.width = width
                    surface.setInk(ink, for: surface.tool)
                } label: {
                    Circle()
                        .fill(Theme.glyphInk.opacity(surface.ink(for: surface.tool).width == width ? 0.92 : 0.5))
                        .frame(width: width / 2 + 3, height: width / 2 + 3)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6).fill(
                                surface.ink(for: surface.tool).width == width ? Theme.chipBg : .clear)
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

    @State private var dragged: CGSize = .zero
    @State private var spot: CGPoint?

    var body: some View {
        Group {
            if edge.isVertical {
                VStack(spacing: 8) { panels }
            } else {
                HStack(spacing: 8) { panels }
            }
        }
            .position(place())
            .offset(dragged)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in dragged = value.translation }
                    .onEnded { value in
                        let dropped = CGPoint(x: place().x + value.translation.width,
                                              y: place().y + value.translation.height)
                        edge = MarkupToolbar.Edge.nearest(to: dropped, in: size)
                        spot = clamp(dropped)
                        dragged = .zero
                    }
            )
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

    /// Along its edge the panel stays where it was dropped; across it, it sits
    /// at a fixed distance, so it never drifts off the screen.
    private func place() -> CGPoint {
        let inset: CGFloat = 60
        let along = spot ?? CGPoint(x: size.width / 2, y: size.height / 2)
        switch edge {
        case .top: return CGPoint(x: along.x, y: inset)
        case .bottom: return CGPoint(x: along.x, y: size.height - inset)
        case .leading: return CGPoint(x: inset, y: along.y)
        case .trailing: return CGPoint(x: size.width - inset, y: along.y)
        }
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 120), size.width - 120),
                y: min(max(point.y, 80), size.height - 80))
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
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        var pick: ((String) -> Bool)?
        /// ⌘Z and ⇧⌘Z. Hop is an accessory app with no Edit menu, so there is no
        /// key equivalent for them to travel on.
        var step: ((Bool) -> Void)?
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
