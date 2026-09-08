import AppKit
import SwiftUI

/// A hint of Hop's own beside whatever the pointer is resting on.
/// SPEC: docs/spec.md — the markup toolbar.
@MainActor
enum MarkupTips {
    private static var panel: NSPanel?
    private static var showing: String?
    private static var pending: DispatchWorkItem?

    static func show(_ text: String, over frame: @escaping () -> CGRect) {
        pending?.cancel()
        let work = DispatchWorkItem { put(text, over: frame()) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    static func hide(_ text: String) {
        pending?.cancel()
        pending = nil
        guard showing == text else { return }
        panel?.orderOut(nil)
        showing = nil
    }

    private static func put(_ text: String, over anchor: CGRect) {
        guard anchor != .zero else { return }
        let host = NSHostingView(rootView: MarkupTipCard(text: text))
        let panel = panel ?? make()
        Self.panel = panel
        panel.contentView = host
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(spot(for: size, over: anchor))
        panel.orderFrontRegardless()
        showing = text
    }

    private static func make() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Above the button when the panel is low on the screen, below it when the
    /// panel is high, and never off the side it is nearest to.
    private static func spot(for size: NSSize, over anchor: CGRect) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? anchor
        let gap: CGFloat = 8
        let above = anchor.maxY + gap
        let below = anchor.minY - size.height - gap
        let y = above + size.height <= bounds.maxY ? above : max(below, bounds.minY + gap)
        let x = min(max(anchor.midX - size.width / 2, bounds.minX + gap),
                    bounds.maxX - size.width - gap)
        return NSPoint(x: x, y: y)
    }
}

private struct MarkupTipCard: View {
    let text: String

    var body: some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(Theme.mono(index == 0 ? 11 : 10))
                    .foregroundStyle(index == 0 ? Theme.textPrimary : Theme.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 320, alignment: .leading)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.isDark ? Color(white: 0.11) : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.controlStroke.opacity(0.6)))
                .shadow(color: .black.opacity(Theme.isDark ? 0.55 : 0.18), radius: 12, y: 5)
        )
        .padding(10)
    }
}

/// WORKAROUND: a SwiftUI view has no screen frame of its own, and the panel it
/// sits in moves; the probe answers where the button is at the moment it is
/// asked, not where it was when it was built.
private struct MarkupTipAnchor: NSViewRepresentable {
    let ready: (@escaping () -> CGRect) -> Void

    final class Probe: NSView {}

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        DispatchQueue.main.async {
            ready { [weak view] in
                guard let view, let window = view.window else { return .zero }
                return window.convertToScreen(view.convert(view.bounds, to: nil))
            }
        }
        return view
    }

    func updateNSView(_ nsView: Probe, context: Context) {}
}

/// WORKAROUND: a popover opens in a window of its own at the ordinary pop-up
/// level, which is UNDER the drawing layer: clicks meant for the colour wheel
/// landed on the picture and drew another mark. SPEC: docs/spec.md
struct MarkupWindowLift: NSViewRepresentable {
    static let level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            lift()
        }

        func lift() {
            guard let window else { return }
            window.level = MarkupWindowLift.level
            window.collectionBehavior.insert(.canJoinAllSpaces)
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ nsView: Probe, context: Context) {
        DispatchQueue.main.async { nsView.lift() }
    }
}

extension View {
    /// For anything that opens in a window of its own over the drawing layer.
    func aboveTheDrawing() -> some View { background(MarkupWindowLift()) }
}

extension View {
    /// Where this view is on screen, asked at the moment the answer is needed.
    func markupAnchor(_ ready: @escaping (@escaping () -> CGRect) -> Void) -> some View {
        background(MarkupTipAnchor(ready: ready))
    }
}

private struct MarkupTipHover: ViewModifier {
    let text: String
    @State private var where_: (() -> CGRect)?

    func body(content: Content) -> some View {
        content
            .background(MarkupTipAnchor { where_ = $0 })
            .onHover { inside in
                if inside, let where_ {
                    MarkupTips.show(text, over: where_)
                } else {
                    MarkupTips.hide(text)
                }
            }
            .onDisappear { MarkupTips.hide(text) }
    }
}

extension View {
    /// Hop's own hint instead of the system tooltip: the panel over the live
    /// screen never becomes key, and a tooltip in it never appeared.
    func markupTip(_ text: String) -> some View { modifier(MarkupTipHover(text: text)) }
}
