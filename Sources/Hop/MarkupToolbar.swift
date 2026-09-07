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

        /// The edge a panel dropped at this point belongs to; the nearest one
        /// wins, and a tie goes to the horizontal, which fits more tools.
        static func nearest(to point: CGPoint, in size: CGSize) -> Edge {
            let distances: [(Edge, CGFloat)] = [
                (.top, point.y), (.bottom, size.height - point.y),
                (.leading, point.x), (.trailing, size.width - point.x),
            ]
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

    @State private var showingInk = false
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
        .popover(isPresented: $showingInk, arrowEdge: edge == .top ? .bottom : .top) {
            MarkupInkPopover(surface: surface, lang: lang)
        }
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
            showingInk.toggle()
        } label: {
            Circle()
                .fill(Color(markupHex: surface.ink(for: surface.tool).hex))
                .frame(width: 17, height: 17)
                .overlay(Circle().strokeBorder(Theme.glyphInk.opacity(0.35), lineWidth: 1.5))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

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

    private func button(for tool: MarkupTool) -> some View {
        let chosen = toolsActive && surface.tool == tool
        return Button {
            surface.tool = tool
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
}

/// Colour and width for the tool in hand; each tool keeps its own pair.
struct MarkupInkPopover: View {
    @ObservedObject var surface: MarkupSurface
    var lang: AppLanguage

    private let palette = ["#FF453A", "#FF9F0A", "#FFD60A", "#32D74B",
                           "#0A84FF", "#BF5AF2", "#FFFFFF", "#1C1C1E"]
    private let widths: [Double] = [2, 4, 9, 18]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(palette, id: \.self) { hex in
                    Button {
                        var ink = surface.ink(for: surface.tool)
                        ink.hex = hex
                        surface.setInk(ink, for: surface.tool)
                    } label: {
                        Circle()
                            .fill(Color(markupHex: hex))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().strokeBorder(
                                    Theme.glyphInk.opacity(surface.ink(for: surface.tool).hex == hex ? 0.9 : 0.2),
                                    lineWidth: surface.ink(for: surface.tool).hex == hex ? 2 : 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Rectangle().fill(Theme.divider).frame(height: 1)

            HStack(spacing: 14) {
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
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 244)
        .background(Theme.background)
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

    @State private var dragged: CGSize = .zero
    @State private var spot: CGPoint?

    var body: some View {
        MarkupToolbar(surface: surface, tools: tools, edge: $edge, lang: lang, trailing: trailing)
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
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        var pick: ((String) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.window?.isVisible == true,
                      !event.modifierFlags.contains(.command),
                      // a field being typed into owns its letters
                      !(self.window?.firstResponder is NSTextView),
                      let letter = event.charactersIgnoringModifiers,
                      self.pick?(letter) == true
                else { return event }
                return nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
