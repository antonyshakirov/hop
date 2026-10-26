import SwiftUI

struct SpaceTabButton: View {
    let icon: String
    var title: String? = nil
    let active: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 15))
                if let title { Text(title).font(Theme.mono(10)).lineLimit(1) }
            }
                .foregroundStyle(active ? Theme.textPrimary : title == nil ? Theme.textTertiary : Theme.textSecondary)
                .frame(width: title == nil ? 56 : nil, height: 28)
                .frame(maxWidth: title == nil ? nil : .infinity)
                .background(active ? Theme.chipBg : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .hoverHighlight(6)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
