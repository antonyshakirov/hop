import CoreGraphics

enum SoundWindowLayout {
    static func frame(current: CGRect, contentHeight: CGFloat, chromeHeight: CGFloat,
                      visible: CGRect, centered: Bool) -> CGRect {
        let available = visible.insetBy(dx: 16, dy: 16)
        let height = min(max(150, contentHeight) + chromeHeight, available.height)
        let width = min(current.width, available.width)
        let x = centered ? visible.midX - width / 2 : min(max(current.minX, available.minX), available.maxX - width)
        let y = centered ? visible.midY - height / 2 : min(max(current.maxY - height, available.minY), available.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
