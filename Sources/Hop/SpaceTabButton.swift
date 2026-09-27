import SwiftUI

struct SpaceTabButton: View {
    let icon: String
    let active: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 56, height: 28)
                .background(active ? Theme.chipBg : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .hoverHighlight(6)
        }
        .buttonStyle(.plain)
    }
}
