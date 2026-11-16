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
    private let loadImage: (String) async -> ClipboardHoverBitmap?
    private var cancelPending: (() -> Void)?
    private var imageTask: Task<Void, Never>?
    private var bitmap: ClipboardHoverBitmap?
    private var delayElapsed = false
    private weak var owner: ClipboardHoverAnchorView?
    private var token = UUID()
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?
    private(set) var panel: NSPanel?

    init(schedule: Scheduler? = nil, containsPointer: ((ClipboardHoverAnchorView) -> Bool)? = nil,
         visibleFrame: ((NSWindow, NSPoint) -> NSRect)? = nil, pointerLocation: (() -> NSPoint)? = nil,
         loadImage: ((String) async -> ClipboardHoverBitmap?)? = nil) {
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
        self.loadImage = loadImage ?? { file in
            await ClipboardHoverImageLoader.shared.load(file: file, directory: ClipboardController.imagesDir)
        }
    }

    func request(from anchor: ClipboardHoverAnchorView) {
        guard owner !== anchor else { return }
        cancel()
        guard anchor.window != nil, !anchor.previewText.isEmpty || anchor.imageFile != nil else { return }
        owner = anchor
        let expected = UUID(); token = expected
        observe(anchor.window!)
        if let file = anchor.imageFile {
            let load = loadImage
            imageTask = Task(priority: .userInitiated) { [weak self, weak anchor] in
                let image = await load(file)
                guard !Task.isCancelled, let self, let anchor, self.token == expected, self.owner === anchor else { return }
                self.imageTask = nil; self.bitmap = image
                if self.delayElapsed { self.present(anchor, expected: expected) }
            }
        }
        cancelPending = schedule(0.5) { [weak self, weak anchor] in
            guard let self, let anchor, self.token == expected, self.owner === anchor else { return }
            self.cancelPending = nil
            self.delayElapsed = true
            self.present(anchor, expected: expected)
        }
    }

    private func present(_ anchor: ClipboardHoverAnchorView, expected: UUID) {
        guard token == expected, owner === anchor else { return }
        guard let parent = anchor.window, parent.isVisible, !anchor.isHiddenOrHasHiddenAncestor,
              containsPointer(anchor) else { cancel(); return }
        if anchor.imageFile != nil, bitmap == nil {
            if imageTask == nil { cancel() }
            return
        }
        show(anchor, parent: parent)
    }

    func cancel(owner anchor: ClipboardHoverAnchorView? = nil) {
        if let anchor, owner !== anchor { return }
        token = UUID(); cancelPending?(); cancelPending = nil; owner = nil
        imageTask?.cancel(); imageTask = nil; bitmap = nil; delayElapsed = false
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
        let maximumWidth = min(360, max(1, min(screen.width - 16, max(240, parent.frame.width - 24))))
        let belowRoom = max(0, pointer.y - 12 - screen.minY - 8)
        let aboveRoom = max(0, screen.maxY - 8 - pointer.y - 18)
        let availableHeight = max(belowRoom, aboveRoom)
        guard availableHeight >= 28 else { cancel(); return }
        let maximum = NSSize(width: maximumWidth, height: min(360, availableHeight))
        let content: NSView
        if anchor.imageFile != nil {
            guard let bitmap, let image = ClipboardHoverContent.image(bitmap, maximum: maximum,
                scale: parent.backingScaleFactor) else { cancel(); return }
            content = image
        } else {
            content = ClipboardHoverContent.text(anchor.previewText, rtl: anchor.rtl, maximum: maximum)
        }
        let width = content.bounds.width, height = content.bounds.height
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
