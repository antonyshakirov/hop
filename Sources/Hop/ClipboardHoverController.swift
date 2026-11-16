import AppKit
import SwiftUI

// SPEC: docs/spec.md — Clipboard, entry hover preview.
@MainActor
final class ClipboardHoverController {
    static let shared = ClipboardHoverController()
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> (() -> Void)
    private let schedule: Scheduler
    private let containsPointer: (ClipboardHoverAnchorView) -> Bool
    private let visibleFrame: (NSWindow, NSPoint) -> NSRect
    private let pointerLocation: () -> NSPoint
    private var cancelPending: (() -> Void)?
    private weak var owner: ClipboardHoverAnchorView?
    private var token = UUID()
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?
    private(set) var panel: NSPanel?

    init(schedule: Scheduler? = nil, containsPointer: ((ClipboardHoverAnchorView) -> Bool)? = nil,
         visibleFrame: ((NSWindow, NSPoint) -> NSRect)? = nil, pointerLocation: (() -> NSPoint)? = nil) {
        self.schedule = schedule ?? { delay, action in
            let work = DispatchWorkItem(block: action)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return { work.cancel() }
        }
        self.containsPointer = containsPointer ?? { $0.pointerInside }
        self.visibleFrame = visibleFrame ?? { parent, pointer in
            NSScreen.screens.first { $0.frame.contains(pointer) }?.visibleFrame
                ?? parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
        }
        self.pointerLocation = pointerLocation ?? { NSEvent.mouseLocation }
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
        let pointer = pointerLocation()
        let screen = visibleFrame(parent, pointer)
        let width = min(360, max(1, min(screen.width - 16, max(240, parent.frame.width - 24))))
        let font = anchor.rtl ? NSFont.systemFont(ofSize: 10, weight: .regular) : NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let style = NSMutableParagraphStyle()
        style.alignment = anchor.rtl ? .right : .left
        style.baseWritingDirection = anchor.rtl ? .rightToLeft : .leftToRight
        let text = NSMutableAttributedString(string: anchor.previewText, attributes: [.font: font,
            .foregroundColor: NSColor(Theme.textPrimary), .paragraphStyle: style])
        if let hint = anchor.actionHint, !hint.isEmpty {
            let hintStyle = NSMutableParagraphStyle()
            hintStyle.alignment = style.alignment; hintStyle.baseWritingDirection = style.baseWritingDirection
            hintStyle.paragraphSpacingBefore = 6
            let hintFont = anchor.rtl ? NSFont.systemFont(ofSize: 9) : NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
            text.append(NSAttributedString(string: "\n" + hint, attributes: [.font: hintFont,
                .foregroundColor: NSColor(Theme.textSecondary), .paragraphStyle: hintStyle]))
        }
        let measured = text.boundingRect(with: NSSize(width: max(1, width - 20), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        let belowRoom = max(0, pointer.y - 12 - screen.minY - 8)
        let aboveRoom = max(0, screen.maxY - 8 - pointer.y - 18)
        let availableHeight = max(belowRoom, aboveRoom)
        guard availableHeight >= 28 else { cancel(); return }
        let height = min(max(28, ceil(measured) + 16), min(360, availableHeight))
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.wantsLayer = true; content.layer?.cornerRadius = 8
        content.layer?.backgroundColor = NSColor(Theme.background).cgColor
        content.layer?.borderWidth = 0.5; content.layer?.borderColor = NSColor(Theme.divider).cgColor
        let label = NSTextField(wrappingLabelWithString: "")
        label.attributedStringValue = text
        label.frame = content.bounds.insetBy(dx: 10, dy: 8)
        label.maximumNumberOfLines = max(1, Int((height - 16) / ceil(font.ascender - font.descender + font.leading)))
        label.cell?.truncatesLastVisibleLine = true
        content.addSubview(label)
        let preview = panel ?? ClipboardHoverPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        preview.isReleasedWhenClosed = false; preview.hidesOnDeactivate = false
        preview.backgroundColor = .clear; preview.isOpaque = false; preview.hasShadow = true
        preview.ignoresMouseEvents = true; preview.animationBehavior = .none
        preview.level = parent.level
        preview.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        preview.contentView = content
        let below = pointer.y - height - 12
        let y = height <= belowRoom ? below : pointer.y + 18
        let frame = NSRect(x: min(max(pointer.x + 10, screen.minX + 8), screen.maxX - width - 8),
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
