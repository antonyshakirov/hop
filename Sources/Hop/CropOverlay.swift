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

    private let handle: CGFloat = 13
    private let least: CGFloat = 24

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Nothing falls through to the window: a drag that misses the frame
            // used to reach the window behind and take it for a walk.
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture().onChanged { _ in }.onEnded { _ in })

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

            // Inside the frame the whole thing moves. The gesture goes on
            // BEFORE .position(): after it, the view fills its parent and the
            // gesture with it, so every grip would answer for the whole picture.
            Color.clear
                .frame(width: box.width, height: box.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(coordinateSpace: .named(Self.space))
                    .onChanged { value in move(by: value.translation) }
                    .onEnded { _ in start = nil })
                .position(x: box.midX, y: box.midY)

            // The dots are decoration; the targets under them are far bigger
            // than the dots, and every SIDE is a target along its whole length.
            ForEach(Grip.allCases, id: \.self) { grip in
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .frame(width: handle, height: handle)
                    .position(spot(of: grip))
                    .allowsHitTesting(false)
            }

            ForEach(Grip.allCases, id: \.self) { grip in
                let target = reach(of: grip)
                Color.clear
                    .frame(width: target.width, height: target.height)
                    .contentShape(Rectangle())
                    // The handle MOVES as it is dragged, so a translation
                    // measured against it drifts and shakes. The pointer's
                    // place in a space that stands still is exact.
                    .gesture(DragGesture(coordinateSpace: .named(Self.space))
                        .onChanged { value in pull(grip, to: value.location) }
                        .onEnded { _ in start = nil })
                    .position(spot(of: grip))
            }
        }
        .frame(width: bounds.width * scale, height: bounds.height * scale)
        .coordinateSpace(name: Self.space)
    }

    private static let space = "crop"

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

    /// How much of the frame each grip answers for: a corner is a square, a
    /// side is a bar down its whole length.
    private func reach(of grip: Grip) -> CGSize {
        let corner = handle * 2.4
        let bar = handle * 1.6
        switch grip {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return CGSize(width: corner, height: corner)
        case .top, .bottom:
            return CGSize(width: max(0, box.width - corner), height: bar)
        case .left, .right:
            return CGSize(width: bar, height: max(0, box.height - corner))
        }
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

    private func pull(_ grip: Grip, to point: CGPoint) {
        let x = point.x / scale
        let y = point.y / scale

        var left = rect.minX
        var top = rect.minY
        var right = rect.maxX
        var bottom = rect.maxY

        switch grip {
        case .topLeft: left = x; top = y
        case .top: top = y
        case .topRight: right = x; top = y
        case .right: right = x
        case .bottomRight: right = x; bottom = y
        case .bottom: bottom = y
        case .bottomLeft: left = x; bottom = y
        case .left: left = x
        }

        left = min(max(0, left), right - least)
        top = min(max(0, top), bottom - least)
        right = max(min(bounds.width, right), left + least)
        bottom = max(min(bounds.height, bottom), top + least)

        rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
