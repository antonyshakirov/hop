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

    /// How many marks there were when the picture was last saved or copied.
    private var settledCount: Int?

    /// Marks that have never left the window. Drawing more AFTER a save makes
    /// it true again: the file on disk is no longer what is on screen.
    var hasUnsavedMarks: Bool {
        !surface.shapes.isEmpty && settledCount != surface.shapes.count
    }

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

    /// A frame drawn with the crop tool becomes the crop and leaves the
    /// document: an outline that stayed would be exported as a red rectangle.
    func applyCropIfDrawn() {
        guard let frame = surface.shapes.last(where: { $0.tool == .crop }),
              frame.points.count > 1 else { return }
        let box = MarkupGeometry.boundingBox(frame.points)
        let rect = CaptureRect(x: box.origin.x, y: box.origin.y,
                               width: box.size.x, height: box.size.y,
                               scale: scale, displayID: rect.displayID)
        surface.dropCropFrames()
        guard rect.isUsable else { return }
        crop = rect
        refreshPreview()
    }

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
        let url = MarkupExport.save(picture, format: format, name: fileName)
        if url != nil { settledCount = surface.shapes.count }
        return url
    }

    func copyToClipboard() {
        MarkupSettings.store(dressing: dressing, watermark: watermark)
        guard let picture = finished() else { return }
        MarkupExport.copy(picture)
        settledCount = surface.shapes.count
    }
}

struct ScreenshotEditorView: View {
    @ObservedObject var editor: ScreenshotEditor
    var lang: AppLanguage
    var onClose: () -> Void

    @State private var saved: URL?
    @State private var showingDressing = false
    @State private var showingWatermark = false

    var body: some View {
        stage
            .background(Theme.panelBackground)
            .frame(minWidth: 960, maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
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
                        .onChange(of: editor.surface.shapes.count) { editor.applyCropIfDrawn() }
                }

                MarkupToolbarLayer(surface: editor.surface,
                                   tools: ScreenshotEditor.tools,
                                   edge: $editor.edge,
                                   size: geometry.size,
                                   lang: lang,
                                   trailing: AnyView(undoRedo),
                                   leading: AnyView(picture),
                                   companion: AnyView(keeping))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(MarkupKeys(surface: editor.surface, tools: ScreenshotEditor.tools))
        }
    }

    /// Done TO the picture rather than drawn on it. SPEC: docs/spec.md
    private var picture: some View {
        HStack(spacing: 4) {
            toolbarButton(glyph: .dressing, lit: editor.dressing.isOn,
                          help: L10n.t(.dressLabel, lang)) { showingDressing.toggle() }
                .popover(isPresented: $showingDressing,
                         arrowEdge: editor.edge == .top ? .bottom : .top) {
                    FrameDressingPopover(editor: editor, lang: lang)
                }

            toolbarButton(glyph: .watermark, lit: editor.watermark.hasSomethingToStamp,
                          help: L10n.t(.markLabel, lang)) { showingWatermark.toggle() }
                .popover(isPresented: $showingWatermark,
                         arrowEdge: editor.edge == .top ? .bottom : .top) {
                    WatermarkPopover(editor: editor, lang: lang)
                }
        }
    }

    /// Where the picture goes when it is done: its name, a copy, a save. Its
    /// own small panel beside the tools rather than a bar across the top — the
    /// window is for the picture.
    private var keeping: some View {
        HStack(spacing: 6) {
            TextField("", text: $editor.fileName)
                .textFieldStyle(.plain)
                .font(Theme.mono(11))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(width: 130, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.fieldBg))

            Button { editor.copyToClipboard() } label: {
                MarkupIcon(glyph: .copy)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.copyLabel, lang))

            Button {
                saved = editor.save()
                if saved != nil { onClose() }
            } label: {
                MarkupIcon(glyph: .save)
                    .foregroundStyle(Theme.playFg)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.playBg))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.featureSave, lang))
        }
    }

    private func toolbarButton(
        glyph: MarkupGlyph, lit: Bool, help: String, run: @escaping () -> Void
    ) -> some View {
        Button(action: run) {
            MarkupIcon(glyph: glyph)
                .foregroundStyle(lit ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 7).fill(lit ? Theme.chipBg : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
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

    /// The picture IS the window. SPEC: docs/spec.md
    private func shownSize(in canvas: CGSize) -> CGSize {
        let available = CGSize(width: max(120, canvas.width),
                               height: max(90, canvas.height))
        let natural: CGSize
        if let preview = editor.dressedPreview {
            natural = CGSize(width: Double(preview.width) / editor.scale,
                             height: Double(preview.height) / editor.scale)
        } else {
            natural = CGSize(width: editor.rect.width, height: editor.rect.height)
        }
        guard natural.width > 0, natural.height > 0 else { return CGSize(width: 80, height: 60) }
        let fit = min(available.width / natural.width, available.height / natural.height)
        let factor = min(fit, 2)
        return CGSize(width: max(80, natural.width * factor),
                      height: max(60, natural.height * factor))
    }
}
