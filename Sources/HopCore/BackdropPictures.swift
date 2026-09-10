import Foundation

/// SPEC: docs/spec.md — "The first loupe or blur reads a still until the stream comes up".
public struct BackdropPictures<Picture> {
    private enum Held {
        case still(Picture)
        case live(Picture)
    }

    private var held: [UInt32: Held] = [:]
    public private(set) var session = 0

    public init() {}

    public subscript(display: UInt32) -> Picture? {
        switch held[display] {
        case .still(let picture), .live(let picture): return picture
        case nil: return nil
        }
    }

    public func isLive(_ display: UInt32) -> Bool {
        if case .live = held[display] { return true }
        return false
    }

    /// Whether the still is now what the display reads.
    @discardableResult
    public mutating func took(still: Picture, on display: UInt32, in session: Int) -> Bool {
        guard session == self.session, !isLive(display) else { return false }
        held[display] = .still(still)
        return true
    }

    public mutating func streamed(_ frame: Picture, on display: UInt32) {
        held[display] = .live(frame)
    }

    public mutating func paused(_ display: UInt32) {
        guard case .live(let last) = held[display] else { return }
        held[display] = .still(last)
    }

    public mutating func forget(_ display: UInt32) {
        held[display] = nil
    }

    public mutating func forgetAll() {
        held = [:]
        session += 1
    }
}
