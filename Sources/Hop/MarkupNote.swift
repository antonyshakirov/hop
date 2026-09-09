import AppKit
import SwiftUI

/// What just happened, said over the button that did it: the save button closes
/// its window and the drawing layer has no window at all, so neither could say
/// anything in place. SPEC: docs/spec.md — "Saying where the picture went".
@MainActor
enum MarkupNote {
    private static var panel: NSPanel?
    private static var fading: DispatchWorkItem?

    static func show(_ text: String, detail: String? = nil, file: URL? = nil,
                     over anchor: CGRect) {
        guard anchor != .zero else { return }
        let card = MarkupNoteCard(
            text: text, detail: detail,
            open: file.map { url in { NSWorkspace.shared.activateFileViewerSelecting([url]) } },
            hold: { hold() }, release: { fade(after: 1.6) }
        )
        let host = NSHostingView(rootView: card)
        let panel = panel ?? make()
        Self.panel = panel
        panel.contentView = host
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(spot(for: size, over: anchor))
        panel.orderFrontRegardless()
        fade(after: file == nil ? 1.8 : 4.5)
    }

    static func hide() {
        fading?.cancel()
        fading = nil
        panel?.orderOut(nil)
    }

    private static func hold() {
        fading?.cancel()
        fading = nil
    }

    private static func fade(after seconds: Double) {
        fading?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { panel?.orderOut(nil) } }
        fading = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private static func make() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        return panel
    }

    /// Above the button, and below it when there is no room; never off the side.
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

private struct MarkupNoteCard: View {
    let text: String
    let detail: String?
    let open: (() -> Void)?
    let hold: () -> Void
    let release: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
            if let detail {
                Text(detail)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 340, alignment: .leading)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.isDark ? Color(white: 0.11) : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.controlStroke.opacity(0.6)))
                .shadow(color: .black.opacity(Theme.isDark ? 0.55 : 0.18), radius: 12, y: 5)
        )
        .padding(10)
        .contentShape(Rectangle())
        .modifier(HandCursorIf(on: open != nil))
        .onHover { inside in inside ? hold() : release() }
        .onTapGesture {
            guard let open else { return }
            MarkupNote.hide()
            open()
        }
    }
}


/// The card is only clickable when it has a file to open.
private struct HandCursorIf: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        on ? AnyView(content.handCursor()) : AnyView(content)
    }
}
