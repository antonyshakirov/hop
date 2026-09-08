import HopCore
import SwiftUI

/// The frame the picture will be cut down to: eight handles, a dimmed outside,
/// and nothing applied until it is asked for. Re-entering shows the WHOLE
/// picture again with the last cut as the frame, so a crop can be taken back.
/// SPEC: docs/spec.md — "Screenshot (capture and mark up)"
struct CropOverlay: View {
    @Binding var rect: CGRect
    /// The whole picture, in the same points `rect` is measured in.
    let bounds: CGSize
    let scale: CGFloat

    private let handle: CGFloat = 11
    private let least: CGFloat = 24

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.45)
                .mask {
                    Rectangle()
                        .overlay {
                            Rectangle()
                                .frame(width: box.width, height: box.height)
                                .position(x: box.midX, y: box.midY)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
                .allowsHitTesting(false)

            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1)
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
                .allowsHitTesting(false)

            thirds

            // Inside the frame the whole thing moves.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
                .gesture(DragGesture()
                    .onChanged { value in move(by: value.translation) }
                    .onEnded { _ in start = nil })

            ForEach(Grip.allCases, id: \.self) { grip in
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                    .frame(width: handle, height: handle)
                    .position(spot(of: grip))
                    .contentShape(Rectangle().inset(by: -8))
                    .gesture(DragGesture()
                        .onChanged { value in pull(grip, by: value.translation) }
                        .onEnded { _ in start = nil })
            }
        }
        .frame(width: bounds.width * scale, height: bounds.height * scale)
    }

    @State private var start: CGRect?

    private var box: CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale,
               width: rect.width * scale, height: rect.height * scale)
    }

    private var thirds: some View {
        ZStack(alignment: .topLeading) {
            ForEach(1..<3) { step in
                Rectangle().fill(Color.white.opacity(0.22))
                    .frame(width: box.width, height: 1)
                    .position(x: box.midX, y: box.minY + box.height / 3 * CGFloat(step))
                Rectangle().fill(Color.white.opacity(0.22))
                    .frame(width: 1, height: box.height)
                    .position(x: box.minX + box.width / 3 * CGFloat(step), y: box.midY)
            }
        }
        .allowsHitTesting(false)
    }

    enum Grip: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private func spot(of grip: Grip) -> CGPoint {
        switch grip {
        case .topLeft: return CGPoint(x: box.minX, y: box.minY)
        case .top: return CGPoint(x: box.midX, y: box.minY)
        case .topRight: return CGPoint(x: box.maxX, y: box.minY)
        case .right: return CGPoint(x: box.maxX, y: box.midY)
        case .bottomRight: return CGPoint(x: box.maxX, y: box.maxY)
        case .bottom: return CGPoint(x: box.midX, y: box.maxY)
        case .bottomLeft: return CGPoint(x: box.minX, y: box.maxY)
        case .left: return CGPoint(x: box.minX, y: box.midY)
        }
    }

    private func move(by translation: CGSize) {
        let from = start ?? rect
        if start == nil { start = rect }
        var moved = from
        moved.origin.x = min(max(0, from.minX + translation.width / scale), bounds.width - from.width)
        moved.origin.y = min(max(0, from.minY + translation.height / scale), bounds.height - from.height)
        rect = moved
    }

    private func pull(_ grip: Grip, by translation: CGSize) {
        let from = start ?? rect
        if start == nil { start = rect }
        let dx = translation.width / scale
        let dy = translation.height / scale

        var left = from.minX
        var top = from.minY
        var right = from.maxX
        var bottom = from.maxY

        switch grip {
        case .topLeft: left += dx; top += dy
        case .top: top += dy
        case .topRight: right += dx; top += dy
        case .right: right += dx
        case .bottomRight: right += dx; bottom += dy
        case .bottom: bottom += dy
        case .bottomLeft: left += dx; bottom += dy
        case .left: left += dx
        }

        left = min(max(0, left), right - least)
        top = min(max(0, top), bottom - least)
        right = max(min(bounds.width, right), left + least)
        bottom = max(min(bounds.height, bottom), top + least)

        rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
