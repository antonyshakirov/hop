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
    @State private var pointer: CGPoint = .zero

    private var frame: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.62)
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

            if let frame {
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)

                Text("\(Int(frame.width * scale)) × \(Int(frame.height * scale))")
                    .font(Theme.mono(11))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.86)))
                    .position(x: frame.midX, y: max(18, frame.minY - 18))
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
