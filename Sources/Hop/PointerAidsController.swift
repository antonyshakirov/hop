import AppKit
import Combine
import HopCore
import SwiftUI

/// The pointer as a presenting tool: a ring around it, a spotlight on it, a
/// trail behind it and a ring at every click.
/// SPEC: docs/spec.md — "Draw over the screen", the presenting pointer.
@MainActor
final class PointerAidsController: ObservableObject {
    @Published var aids: PointerAids {
        didSet {
            MarkupSettings.savePointerAids(aids)
            aids.isOn ? start() : stop()
        }
    }

    @Published private(set) var at: NSPoint = .zero
    @Published private(set) var trail: [(point: NSPoint, born: TimeInterval)] = []
    @Published private(set) var clicks: [(point: NSPoint, born: TimeInterval)] = []
    /// Redrawn on every tick so the fading marks keep fading with no input.
    @Published private(set) var now: TimeInterval = 0

    private var watchers: [Any] = []
    private var ticker: Timer?
    private let opened = Date()

    init() {
        aids = MarkupSettings.pointerAids()
    }

    /// Watching costs nothing while nothing is drawn, so it follows `isOn`.
    func start() {
        guard watchers.isEmpty, aids.isOn else { return }
        at = NSEvent.mouseLocation
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        let presses: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves.union(presses), handler: { [weak self] event in
            MainActor.assumeIsolated { self?.saw(event) }
        }) {
            watchers.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves.union(presses), handler: { [weak self] event in
            MainActor.assumeIsolated { self?.saw(event) }
            return event
        }) {
            watchers.append(local)
        }
        let ticker = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    func stop() {
        for watcher in watchers { NSEvent.removeMonitor(watcher) }
        watchers.removeAll()
        ticker?.invalidate()
        ticker = nil
        trail.removeAll()
        clicks.removeAll()
    }

    private func saw(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        at = point
        let stamp = Date().timeIntervalSince(opened)
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            if aids.clicks { clicks.append((point, stamp)) }
        default:
            if aids.trail, trail.last.map({ hypot($0.point.x - point.x, $0.point.y - point.y) > 4 }) ?? true {
                trail.append((point, stamp))
            }
        }
    }

    private func tick() {
        now = Date().timeIntervalSince(opened)
        trail.removeAll { now - $0.born >= PointerAids.trailLife }
        clicks.removeAll { now - $0.born >= PointerAids.clickLife }
    }
}
