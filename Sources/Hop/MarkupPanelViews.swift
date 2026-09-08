import HopCore
import SwiftUI

/// The screenshot module's row in the panel: three ways to take one, kept on
/// the same line as the name so the card stays one row tall.
struct ShotView: View {
    @ObservedObject var shot: CaptureController
    var lang: AppLanguage
    var closePanel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 16)
            // German runs to "bildschirmfoto"; the buttons keep their size and
            // the name gives way instead.
            Text(L10n.t(.shotLabel, lang))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            if shot.lastRect != nil {
                iconButton("arrow.counterclockwise", help: L10n.t(.shotRepeat, lang)) {
                    shot.capture(.repeatLast)
                }
            }
            button(.shotArea) { shot.capture(.area) }
            button(.shotWindow) { shot.capture(.window) }
            button(.shotScreen) { shot.capture(.screen) }
        }
    }

    private func button(_ key: L10nKey, run: @escaping () -> Void) -> some View {
        Button {
            fire(run)
        } label: {
            Text(L10n.t(key, lang))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.chipBg))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .modifier(Theme.HoverHighlight(cornerRadius: 7))
    }

    private func iconButton(_ symbol: String, help: String, run: @escaping () -> Void) -> some View {
        Button {
            fire(run)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.chipBg))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(Theme.HoverHighlight(cornerRadius: 7))
        .help(help)
    }

    private func fire(_ run: @escaping () -> Void) {
        closePanel()
        // The panel is a popover: it must be gone before the frame goes up, or
        // it lands in the picture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: run)
    }
}

/// The drawing module's row: one button that raises the layer.
struct ScreenAnnotateRow: View {
    @ObservedObject var annotate: ScreenAnnotateController
    var lang: AppLanguage
    var closePanel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.tip")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 16)
            Text(L10n.t(.annotateLabel, lang))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Button {
                closePanel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    annotate.toggle()
                }
            } label: {
                Text(L10n.t(annotate.isUp ? .annotateExit : .annotateStart, lang))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.chipBg))
            }
            .buttonStyle(.plain)
            .fixedSize()
            .modifier(Theme.HoverHighlight(cornerRadius: 7))
        }
    }
}
