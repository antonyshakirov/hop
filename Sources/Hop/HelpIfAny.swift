import SwiftUI

extension View {
    /// `.help` that accepts nothing: an empty tooltip is worse than none, and a
    /// shared control cannot always name what it does for its caller.
    @ViewBuilder func helpIfAny(_ text: String?) -> some View {
        if let text, !text.isEmpty { self.help(text) } else { self }
    }
}
