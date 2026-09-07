import HopCore
import SwiftUI

/// The screenshot module's row in the panel: three ways to take one.
struct ShotView: View {
    @ObservedObject var shot: CaptureController
    var lang: AppLanguage
    var closePanel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MarkupIcon(glyph: .crop, size: 15)
                    .foregroundStyle(Theme.glyphInk.opacity(Theme.glyphInkSecondary))
                Text(L10n.t(.shotLabel, lang))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            HStack(spacing: 8) {
                button(.shotArea) { shot.capture(.area) }
                button(.shotWindow) { shot.capture(.window) }
                button(.shotScreen) { shot.capture(.screen) }
                if shot.lastRect != nil {
                    button(.shotRepeat) { shot.capture(.repeatLast) }
                }
            }
        }
    }

    private func button(_ key: L10nKey, run: @escaping () -> Void) -> some View {
        Button {
            closePanel()
            // The panel is a popover: it must be gone before the frame goes up,
            // or it lands in the picture.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: run)
        } label: {
            Text(L10n.t(key, lang))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.chipBg))
        }
        .buttonStyle(.plain)
        .modifier(Theme.HoverHighlight(cornerRadius: 7))
    }
}

/// The drawing module's row: one button that raises the layer.
struct ScreenAnnotateRow: View {
    @ObservedObject var annotate: ScreenAnnotateController
    var lang: AppLanguage
    var closePanel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            MarkupIcon(glyph: .pencil, size: 15)
                .foregroundStyle(Theme.glyphInk.opacity(Theme.glyphInkSecondary))
            Text(L10n.t(.annotateLabel, lang))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                closePanel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    annotate.toggle()
                }
            } label: {
                Text(L10n.t(annotate.isUp ? .annotateExit : .annotateStart, lang))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.chipBg))
            }
            .buttonStyle(.plain)
            .modifier(Theme.HoverHighlight(cornerRadius: 7))
        }
    }
}
