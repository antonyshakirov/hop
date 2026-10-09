import Foundation

enum MediaExportQuality: Equatable, Sendable {
    case full
    case compressed(Int)

    var fraction: Double {
        if case .compressed(let percent) = self { return Double(min(100, max(1, percent))) / 100 }
        return 1
    }
}
