import AppKit
import HopCore
import SwiftUI

/// One captured frame being marked up: the picture, the marks over it, the
/// dressing around it and the watermark on top.
@MainActor
final class ScreenshotEditor: ObservableObject {
    @Published var surface = MarkupSurface()
    @Published var dressing: FrameDressing
    @Published var watermark: Watermark
    @Published var fileName: String
    @Published var format: String
    @Published var crop: CaptureRect?
    @Published var edge: MarkupToolbar.Edge = .bottom
    @Published private(set) var dressedPreview: CGImage?

    let base: CGImage
    let rect: CaptureRect

    init(base: CGImage, rect: CaptureRect) {
        self.base = base
        self.rect = rect
        let format = UserDefaults.standard.string(forKey: "shotFormat") ?? "png"
        self.format = format
        fileName = ScreenshotNaming.fileName(at: Date(), calendar: .current, format: format)
        dressing = MarkupSettings.frameDressing()
        watermark = MarkupSettings.watermark()
    }

    /// The tools this surface offers: no fading ink on a picture that will be
    /// saved, and every tool that needs pixels under it lives only here.
    static let tools: [MarkupTool] = [
        .crop, .pencil, .marker, .arrow, .line, .rectangle,
        .oval, .steps, .text, .magnifier, .blur, .eraser,
    ]

    var scale: Double { rect.scale }

    func refreshPreview() {
        guard dressing.isOn || watermark.hasSomethingToStamp else {
            dressedPreview = nil
            return
        }
        dressedPreview = MarkupExport.render(
            base: base, shapes: surface.shapes, scale: scale,
            crop: crop, dressing: dressing, watermark: watermark
        )
    }

    func finished() -> CGImage? {
        MarkupExport.render(base: base, shapes: surface.shapes, scale: scale,
                            crop: crop, dressing: dressing, watermark: watermark)
    }

    func save() -> URL? {
        MarkupSettings.store(dressing: dressing, watermark: watermark)
        guard let picture = finished() else { return nil }
        return MarkupExport.save(picture, format: format, name: fileName)
    }

    func copyToClipboard() {
        MarkupSettings.store(dressing: dressing, watermark: watermark)
        guard let picture = finished() else { return }
        MarkupExport.copy(picture)
    }
}

struct ScreenshotEditorView: View {
    @ObservedObject var editor: ScreenshotEditor
    var lang: AppLanguage
    var onClose: () -> Void

    @State private var saved: URL?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.divider).frame(height: 1)
            HStack(spacing: 0) {
                FrameDressingPanel(editor: editor, lang: lang)
                    .frame(width: 240)
                Rectangle().fill(Theme.divider).frame(width: 1)
                stage
            }
        }
        .background(Theme.panelBackground)
        .frame(minWidth: 980, minHeight: 640)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(L10n.t(.shotLabel, lang))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textTertiary)

            Spacer()

            TextField("", text: $editor.fileName)
                .textFieldStyle(.plain)
                .font(Theme.mono(12))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.fieldBg))
                .frame(width: 260)

            Picker("", selection: $editor.format) {
                Text("png").tag("png")
                Text("jpg").tag("jpg")
            }
            .labelsHidden()
            .frame(width: 84)

            Button(L10n.t(.copyLabel, lang)) { editor.copyToClipboard() }
                .buttonStyle(.plain)
                .font(Theme.mono(12))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.controlStroke))

            Button(L10n.t(.featureSave, lang)) {
                saved = editor.save()
                if saved != nil { onClose() }
            }
            .buttonStyle(.plain)
            .font(Theme.mono(12, weight: .semibold))
            .foregroundStyle(Theme.playFg)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.playBg))
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    private var stage: some View {
        GeometryReader { geometry in
            let shown = shownSize(in: geometry.size)
            ZStack {
                Theme.background.opacity(0.4)

                if let preview = editor.dressedPreview {
                    Image(decorative: preview, scale: 1)
                        .resizable().scaledToFit()
                        .frame(width: shown.width, height: shown.height)
                } else {
                    MarkupCanvas(surface: editor.surface,
                                 background: Image(decorative: editor.base, scale: 1),
                                 scale: shown.width / editor.rect.width)
                        .frame(width: shown.width, height: shown.height)
                        .clipped()
                }

                VStack {
                    Spacer()
                    MarkupToolbar(surface: editor.surface,
                                  tools: ScreenshotEditor.tools,
                                  edge: $editor.edge,
                                  lang: lang,
                                  trailing: AnyView(undoRedo))
                        .padding(.bottom, 26)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var undoRedo: some View {
        HStack(spacing: 4) {
            Button { editor.surface.undo() } label: {
                MarkupIcon(glyph: .undo)
                    .foregroundStyle(editor.surface.canUndo ? Theme.textSecondary : Theme.textTertiary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button { editor.surface.redo() } label: {
                MarkupIcon(glyph: .redo)
                    .foregroundStyle(editor.surface.canRedo ? Theme.textSecondary : Theme.textTertiary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
    }

    private func shownSize(in canvas: CGSize) -> CGSize {
        let available = CGSize(width: canvas.width - 80, height: canvas.height - 120)
        let ratio = editor.rect.height / max(editor.rect.width, 1)
        var width = min(available.width, editor.rect.width)
        var height = width * ratio
        if height > available.height {
            height = available.height
            width = height / max(ratio, 0.0001)
        }
        return CGSize(width: max(80, width), height: max(60, height))
    }
}
