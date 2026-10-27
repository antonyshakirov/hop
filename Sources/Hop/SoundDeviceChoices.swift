import SwiftUI

/// Measure real rows before choosing a scroll viewport; row counts cannot account
/// for wrapped device names or a saved device that is currently unavailable.
struct SoundDeviceChoices<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            ScrollView { content }
        }
        .frame(width: 300)
        .frame(maxHeight: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.panelBackground)
        .hopLayoutDirection()
    }
}
