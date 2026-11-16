import AppKit
import SwiftUI

// SPEC: docs/spec.md — Clipboard, entry hover preview.
@MainActor
final class ClipboardHoverController {
    static let shared = ClipboardHoverController()
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> (() -> Void)
    private let schedule: Scheduler
    private let containsPointer: (ClipboardHoverAnchorView) -> Bool
    private let visibleFrame: (NSWindow) -> NSRect
    private var cancelPending: (() -> Void)?
    private weak var owner: ClipboardHoverAnchorView?
    private var token = UUID()
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?
    private(set) var panel: NSPanel?

    init(schedule: Scheduler? = nil, containsPointer: ((ClipboardHoverAnchorView) -> Bool)? = nil,
         visibleFrame: ((NSWindow) -> NSRect)? = nil) {
        self.schedule = schedule ?? { delay, action in
            let work = DispatchWorkItem(block: action)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return { work.cancel() }
        }
        self.containsPointer = containsPointer ?? { $0.pointerInside }
        self.visibleFrame = visibleFrame ?? { $0.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? $0.frame }
    }

    func request(from anchor: ClipboardHoverAnchorView) {
        guard owner !== anchor else { return }
        cancel()
        guard anchor.window != nil, !anchor.previewText.isEmpty else { return }
        owner = anchor
        let expected = UUID(); token = expected
        observe(anchor.window!)
        cancelPending = schedule(0.5) { [weak self, weak anchor] in
            guard let self, let anchor, self.token == expected, self.owner === anchor else { return }
            self.cancelPending = nil
            guard let parent = anchor.window, parent.isVisible, !anchor.isHiddenOrHasHiddenAncestor,
                  self.containsPointer(anchor) else { self.cancel(); return }
            self.show(anchor, parent: parent)
        }
    }

    func cancel(owner anchor: ClipboardHoverAnchorView? = nil) {
        if let anchor, owner !== anchor { return }
        token = UUID(); cancelPending?(); cancelPending = nil; owner = nil
        for observation in observers { NotificationCenter.default.removeObserver(observation) }
        observers.removeAll()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }; eventMonitor = nil
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil); panel.contentView = nil
        }
    }

    private func observe(_ parent: NSWindow) {
        let center = NotificationCenter.default
        for name in [NSPopover.didCloseNotification, NSApplication.didHideNotification,
                     NSApplication.didResignActiveNotification, NSApplication.willTerminateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            })
        }
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification, NSWindow.didMoveNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            })
        }
        observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
            object: parent, queue: .main) { [weak self, weak parent] _ in
            MainActor.assumeIsolated {
                if parent?.isVisible != true || parent?.occlusionState.contains(.visible) != true { self?.cancel() }
            }
        })
        if let clip = owner?.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification,
                object: clip, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } })
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) {
            [weak self] event in
            MainActor.assumeIsolated { self?.cancel() }
            return event
        }
    }

    private func show(_ anchor: ClipboardHoverAnchorView, parent: NSWindow) {
        let screen = visibleFrame(parent)
        let width = min(400, max(1, screen.width - 16))
        let font = anchor.rtl ? NSFont.systemFont(ofSize: 12, weight: .medium) : NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let style = NSMutableParagraphStyle()
        style.alignment = anchor.rtl ? .right : .left
        style.baseWritingDirection = anchor.rtl ? .rightToLeft : .leftToRight
        let text = NSAttributedString(string: anchor.previewText, attributes: [.font: font,
            .foregroundColor: NSColor(Theme.textPrimary), .paragraphStyle: style])
        let measured = text.boundingRect(with: NSSize(width: max(1, width - 24), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        let height = min(max(32, ceil(measured) + 20), max(32, min(360, screen.height - 16)))
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.wantsLayer = true; content.layer?.cornerRadius = 8
        content.layer?.backgroundColor = NSColor(Theme.background).cgColor
        content.layer?.borderWidth = 1; content.layer?.borderColor = NSColor(Theme.controlStroke).cgColor
        let label = NSTextField(wrappingLabelWithString: "")
        label.attributedStringValue = text
        label.frame = content.bounds.insetBy(dx: 12, dy: 10)
        label.maximumNumberOfLines = max(1, Int((height - 20) / ceil(font.ascender - font.descender + font.leading)))
        label.cell?.truncatesLastVisibleLine = true
        content.addSubview(label)
        let preview = panel ?? ClipboardHoverPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        preview.isReleasedWhenClosed = false; preview.hidesOnDeactivate = false
        preview.backgroundColor = .clear; preview.isOpaque = false; preview.hasShadow = true
        preview.ignoresMouseEvents = true; preview.animationBehavior = .none
        preview.level = parent.level
        preview.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        preview.contentView = content
        let rect = parent.convertToScreen(anchor.convert(anchor.visibleRect, to: nil))
        let below = rect.minY - height - 6
        let y = below >= screen.minY + 8 ? below : rect.maxY + 6
        let frame = NSRect(x: min(max(rect.minX + 12, screen.minX + 8), screen.maxX - width - 8),
            y: min(max(y, screen.minY + 8), screen.maxY - height - 8), width: width, height: height)
        preview.setFrame(frame, display: false)
        parent.addChildWindow(preview, ordered: .above)
        preview.orderFront(nil); panel = preview
    }
}

private final class ClipboardHoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
