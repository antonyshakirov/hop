import HopCore
import SwiftUI

/// The frame drawn while an area is being chosen: the veil, the bright
/// selection, its size, and a loupe showing the pixels under the pointer.
///
/// Coordinates are the display's own, top left down — the same ones the
/// captured image is cropped in, so nothing has to be converted twice.
struct CaptureSelectionView: View {
    let screenSize: CGSize
    let scale: CGFloat
    let lang: AppLanguage
    var onPick: (CaptureRect) -> Void
    var onWindowMode: () -> Void
    var onRepeat: () -> Void
    var onCancel: () -> Void

    @State private var start: CGPoint?
    @State private var current: CGPoint?
    @State private var pointer: CGPoint?

    /// Light enough that the screen underneath stays readable while the frame
    /// is drawn — the system's own picker dims about this much.
    private let veil = 0.24

    private var frame: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(veil)
                .mask {
                    Rectangle()
                        .overlay {
                            if let frame {
                                Rectangle()
                                    .frame(width: frame.width, height: frame.height)
                                    .position(x: frame.midX, y: frame.midY)
                                    .blendMode(.destinationOut)
                            }
                        }
                        .compositingGroup()
                }

            if frame == nil, let pointer {
                crosshair(at: pointer)
            }

            if let frame {
                border(frame)
                if let start { anchor(at: start) }
            }

            if let readout = readout, let pointer {
                Text(readout)
                    .font(Theme.mono(11))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.8)))
                    .fixedSize()
                    .position(badgeSpot(near: pointer))
            }

            hints
                .position(x: screenSize.width / 2, y: screenSize.height - 54)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if start == nil { start = value.startLocation }
                    current = value.location
                    pointer = value.location
                }
                .onEnded { _ in
                    defer { start = nil; current = nil }
                    guard let frame else { return }
                    let rect = CaptureRect(x: frame.minX, y: frame.minY,
                                           width: frame.width, height: frame.height,
                                           scale: scale, displayID: 0)
                    guard rect.isUsable else { return }
                    onPick(rect)
                }
        )
        .onExitCommand(perform: onCancel)
        .background(CaptureKeyCatcher(onSpace: onWindowMode, onRepeat: onRepeat, onCancel: onCancel))
        .background(CapturePointerTracker(onMove: { pointer = $0 }, onLeave: { pointer = nil }))
    }

    /// Where the drag will begin, and where it is: the size once there is one,
    /// the pointer's own place before that.
    private var readout: String? {
        if let frame {
            return "\(Int((frame.width * scale).rounded())) × \(Int((frame.height * scale).rounded()))"
        }
        guard let pointer else { return nil }
        return "\(Int((pointer.x * scale).rounded())), \(Int((pointer.y * scale).rounded()))"
    }

    /// The badge rides below and right of the pointer, and flips at the edges
    /// so it never leaves the display.
    private func badgeSpot(near pointer: CGPoint) -> CGPoint {
        let width: CGFloat = 96
        let height: CGFloat = 24
        var x = pointer.x + 16 + width / 2
        var y = pointer.y + 18 + height / 2
        if x + width / 2 > screenSize.width - 8 { x = pointer.x - 16 - width / 2 }
        if y + height / 2 > screenSize.height - 8 { y = pointer.y - 18 - height / 2 }
        return CGPoint(x: x, y: y)
    }

    /// Hairlines all the way across, so the row and column the drag starts on
    /// are visible before the first pixel is drawn.
    private func crosshair(at point: CGPoint) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.white.opacity(0.55))
                .frame(width: screenSize.width, height: 1)
                .position(x: screenSize.width / 2, y: point.y)
            Rectangle().fill(Color.white.opacity(0.55))
                .frame(width: 1, height: screenSize.height)
                .position(x: point.x, y: screenSize.height / 2)
            Circle().fill(Color.white)
                .frame(width: 5, height: 5)
                .position(point)
        }
        .shadow(color: .black.opacity(0.5), radius: 1)
        .allowsHitTesting(false)
    }

    /// The corner the drag began in stays marked while the frame is stretched.
    private func anchor(at point: CGPoint) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 7, height: 7)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 1))
            .position(point)
            .allowsHitTesting(false)
    }

    /// A dark hairline under the white one: a white frame alone disappears on
    /// a white window.
    private func border(_ frame: CGRect) -> some View {
        ZStack {
            Rectangle()
                .strokeBorder(Color.black.opacity(0.5), lineWidth: 3)
                .frame(width: frame.width + 2, height: frame.height + 2)
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1)
                .frame(width: frame.width, height: frame.height)
        }
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
    }

    private var hints: some View {
        HStack(spacing: 18) {
            hint("space", L10n.t(.shotHintWindow, lang))
            Rectangle().fill(Color.white.opacity(0.16)).frame(width: 1, height: 16)
            hint("r", L10n.t(.shotHintRepeat, lang))
            Rectangle().fill(Color.white.opacity(0.16)).frame(width: 1, height: 16)
            hint("esc", L10n.t(.shotHintCancel, lang))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.9)))
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(Theme.mono(11))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)))
            Text(text).font(Theme.mono(11)).foregroundStyle(Color.white.opacity(0.66))
        }
    }
}

/// Space, R and Escape while the frame is up. SwiftUI has no key handler for a
/// borderless window that never becomes key in the usual way.
private struct CaptureKeyCatcher: NSViewRepresentable {
    let onSpace: () -> Void
    let onRepeat: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.onSpace = onSpace
        view.onRepeat = onRepeat
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        var onSpace: (() -> Void)?
        var onRepeat: (() -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 49: onSpace?()
            case 15: onRepeat?()
            case 53: onCancel?()
            default: super.keyDown(with: event)
            }
        }
    }
}

/// The pointer's place while nothing is being dragged — SwiftUI's own gestures
/// only report a moving mouse once a button is down, and the crosshair has to
/// be there before that.
private struct CapturePointerTracker: NSViewRepresentable {
    let onMove: (CGPoint) -> Void
    let onLeave: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackerView()
        view.onMove = onMove
        view.onLeave = onLeave
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? TrackerView else { return }
        view.onMove = onMove
        view.onLeave = onLeave
    }

    final class TrackerView: NSView {
        var onMove: ((CGPoint) -> Void)?
        var onLeave: (() -> Void)?
        private var area: NSTrackingArea?

        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let fresh = NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self
            )
            addTrackingArea(fresh)
            area = fresh
        }

        override func mouseMoved(with event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }

        override func mouseDragged(with event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            onLeave?()
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.crosshair.set()
        }
    }
}
