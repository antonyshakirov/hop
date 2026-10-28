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

struct SoundDeviceChoiceRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark" : "circle")
                Text(title).lineLimit(2)
                Spacer(minLength: 0)
            }.font(Theme.mono(11)).padding(.horizontal, 8).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(SoundTextActionStyle(normal: selected ? Theme.textPrimary : Theme.textSecondary))
    }
}
