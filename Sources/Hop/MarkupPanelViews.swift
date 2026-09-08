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

            Spacer(minLength: 8)

            HStack(spacing: 11) {
                button("rectangle.dashed", .shotArea) { shot.capture(.area) }
                button("macwindow", .shotWindow) { shot.capture(.window) }
                button("display", .shotScreen) { shot.capture(.screen) }
            }
        }
    }

    private func button(_ symbol: String, _ key: L10nKey,
                        run: @escaping () -> Void) -> some View {
        ShotButton(symbol: symbol, title: L10n.t(key, lang)) { fire(run) }
    }

    private func fire(_ run: @escaping () -> Void) {
        closePanel()
        // The panel is a popover: it must be gone before the frame goes up, or
        // it lands in the picture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: run)
    }
}

/// One way of taking a shot. The glyph carries the meaning — a dashed frame, a
/// window, a display — and the word confirms it; the two light up together.
private struct ShotButton: View {
    let symbol: String
    let title: String
    var run: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5))
                Text(title)
                    .font(Theme.mono(11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
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
            Spacer(minLength: 8)
            Button {
                closePanel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    annotate.toggle()
                }
            } label: {
                HoverLabel(text: L10n.t(annotate.isUp ? .annotateExit : .annotateStart, lang),
                           color: annotate.isUp ? Theme.editing : Theme.textSecondary)
                    .lineLimit(1)
                    .frame(height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }
}
