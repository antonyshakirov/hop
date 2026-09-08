import AppKit
import Combine
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
    /// The frame being chosen, while the crop tool is in hand.
    @Published var cropDraft: CGRect?
    @Published var edge: MarkupToolbar.Edge = .bottom
    @Published private(set) var dressedPreview: CGImage?
    /// The picture with blur and the loupe already in it, under the marks.
    @Published private(set) var backdrop: CGImage?

    private var watches: Set<AnyCancellable> = []

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
        // Every shot starts clean. Carrying the last one's dressing and mark
        // into the next meant a plain screenshot came up wearing whatever the
        // one before it was dressed in (Anton, 2026-09-08). What the mark SAYS
        // is remembered — those are the user's own words, not a setting — and
        // comes back the moment the mark is switched on.
        dressing = .standard
        var mark = Watermark.standard
        let remembered = MarkupSettings.watermark()
        mark.text = remembered.text
        mark.imageName = remembered.imageName
        watermark = mark

        // The view watches the EDITOR, not the surface: without these the tool
        // could change and nothing here would hear it.
        surface.$tool
            .sink { [weak self] tool in
                guard let self else { return }
                if tool == .crop { self.beginCropping() } else { self.cropDraft = nil }
            }
            .store(in: &watches)

        surface.$shapes
            .sink { [weak self] shapes in
                guard let self else { return }
                self.backdrop = MarkupRender.effects(base: self.base, shapes: shapes, scale: self.scale)
                self.refreshPreview()
            }
            .store(in: &watches)
    }

    /// The tools this surface offers: no fading ink on a picture that will be
    /// saved, and every tool that needs pixels under it lives only here.
    static let tools: [MarkupTool] = [
        .crop, .pencil, .fadingInk, .marker, .arrow, .line, .rectangle,
        .oval, .steps, .text, .magnifier, .blur, .eraser,
    ]

    var scale: Double { rect.scale }

    /// The whole picture, in points.
    var full: CGSize { CGSize(width: rect.width, height: rect.height) }

    /// What the window shows: the cut, unless the cut is being chosen.
    var visible: CGRect {
        if cropDraft != nil { return CGRect(origin: .zero, size: full) }
        guard let crop, crop.isUsable else { return CGRect(origin: .zero, size: full) }
        return CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)
    }

    func beginCropping() {
        guard cropDraft == nil else { return }
        if let crop, crop.isUsable {
            cropDraft = CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)
        } else {
            cropDraft = CGRect(origin: .zero, size: full)
        }
    }

    func applyCrop() {
        defer { cropDraft = nil }
        guard let frame = cropDraft else { return }
        let cut = CaptureRect(x: frame.minX, y: frame.minY,
                              width: frame.width, height: frame.height,
                              scale: scale, displayID: rect.displayID)
        crop = cut.isUsable && frame.size != full ? cut : nil
        refreshPreview()
    }

    func resetCrop() {
        cropDraft = CGRect(origin: .zero, size: full)
    }

    private var refreshPending = false

    /// A slider dragged is a render per frame at the shot's full resolution, so
    /// the calls are coalesced. Waiting for the slider to be let go instead
    /// meant nothing moved while it was being moved.
    func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.refreshPreview()
        }
    }

    func refreshPreview() {
        guard dressing.isOn || watermark.hasSomethingToStamp else {
            dressedPreview = nil
            return
        }
        dressedPreview = MarkupExport.render(
            base: base, shapes: surface.lasting, scale: scale,
            crop: crop, dressing: dressing, watermark: watermark
        )
    }

    func finished() -> CGImage? {
        MarkupExport.render(base: base, shapes: surface.lasting, scale: scale,
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
    @State private var copied = false
    @State private var showingDressing = false
    @State private var showingWatermark = false

    var body: some View {
        stage
            .background(Theme.panelBackground)
            .frame(minWidth: 960, maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
    }

    private var stage: some View {
        GeometryReader { geometry in
            let seen = editor.visible
            let dressed = editor.cropDraft == nil ? editor.dressedPreview : nil
            let natural = dressed.map {
                CGSize(width: Double($0.width) / editor.scale, height: Double($0.height) / editor.scale)
            } ?? seen.size
            let s = fitScale(natural, in: geometry.size)
            ZStack {
                Theme.background.opacity(0.4)

                if let dressed {
                    // The dressing widens the canvas, so what is shown is no
                    // longer the shot's own shape and nothing has to be offset.
                    Image(decorative: dressed, scale: 1)
                        .resizable().scaledToFit()
                        .frame(width: natural.width * s, height: natural.height * s)
                } else {
                    Color.clear
                        .frame(width: seen.width * s, height: seen.height * s)
                        .overlay(alignment: .topLeading) {
                            MarkupCanvas(surface: editor.surface,
                                         background: Image(decorative: editor.backdrop ?? editor.base,
                                                           scale: 1),
                                         scale: s)
                                .frame(width: editor.full.width * s, height: editor.full.height * s)
                                .allowsHitTesting(editor.cropDraft == nil)
                                .offset(x: -seen.minX * s, y: -seen.minY * s)
                        }
                        .clipped()
                        .overlay(alignment: .topLeading) {
                            if editor.cropDraft != nil {
                                CropOverlay(rect: Binding(
                                    get: { editor.cropDraft ?? .zero },
                                    set: { editor.cropDraft = $0 }
                                ), bounds: editor.full, scale: s)
                            }
                        }
                }

                MarkupToolbarLayer(surface: editor.surface,
                                   tools: ScreenshotEditor.tools,
                                   edge: $editor.edge,
                                   size: geometry.size,
                                   lang: lang,
                                   trailing: AnyView(undoRedo),
                                   leading: AnyView(picture),
                                   companion: AnyView(companion))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(MarkupKeys(surface: editor.surface, tools: ScreenshotEditor.tools))
        }
    }

    /// While a frame is being chosen the keeping panel gives way to the two
    /// answers the frame needs.
    @ViewBuilder
    private var companion: some View {
        if editor.cropDraft != nil { cropping } else { keeping }
    }

    private var cropping: some View {
        HStack(spacing: 6) {
            Button { editor.resetCrop() } label: {
                MarkupIcon(glyph: .undo)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.resetDefaults, lang))

            Button {
                editor.applyCrop()
                editor.surface.tool = .pencil
            } label: {
                MarkupIcon(glyph: .crop)
                    .foregroundStyle(Theme.playFg)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.playBg))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.mkCrop, lang))
        }
        .frame(height: 32)
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
                // The focus ring grows the field, and the whole panel jumps
                // with it the moment the name is clicked into.
                .focusEffectDisabled()
                .padding(.horizontal, 8)
                .frame(width: 130, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.fieldBg))

            Button {
                editor.copyToClipboard()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { copied = false }
            } label: {
                MarkupIcon(glyph: copied ? .done : .copy)
                    .foregroundStyle(copied ? Theme.accentGreen : Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(copied ? Theme.chipBg : .clear))
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
            Button { editor.surface.clear() } label: {
                MarkupIcon(glyph: .clear)
                    .foregroundStyle(editor.surface.shapes.isEmpty
                                     ? Theme.textTertiary : Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.annotateClear, lang))

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
    private func fitScale(_ natural: CGSize, in canvas: CGSize) -> CGFloat {
        guard natural.width > 0, natural.height > 0 else { return 1 }
        let fit = min(max(120, canvas.width) / natural.width,
                      max(90, canvas.height) / natural.height)
        return min(fit, 2)
    }
}
