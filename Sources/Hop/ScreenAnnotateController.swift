import AppKit
import Combine
import HopCore
import ScreenCaptureKit
import SwiftUI

/// Drawing over the live screen: a transparent layer on every display, and a
/// switch between taking the mouse and letting it through.
///
/// The yellow border in the drawing mode is not decoration — a layer silently
/// eating clicks reads as a frozen Mac.
@MainActor
final class ScreenAnnotateController: ObservableObject {
    @Published private(set) var isUp = false
    @Published var isDrawing = true
    @Published var edge: MarkupToolbar.Edge = .bottom
    let surface = MarkupSurface()

    /// Fading ink and the marker belong here; crop, blur and the magnifier need
    /// pixels this layer does not have.
    static let tools: [MarkupTool] = [
        .select, .pencil, .fadingInk, .marker, .arrow, .line,
        .rectangle, .oval, .steps, .text, .eraser,
    ]

    private let overlay = MarkupOverlayController()
    private var toolbarWindow: MarkupToolbarWindow?
    private var toolWatch: AnyCancellable?

    func toggle() {
        isUp ? exit() : show()
    }

    func show() {
        guard !isUp, !Snapshot.active else { return }
        isUp = true
        isDrawing = true
        overlay.show { [weak self] screen in
            guard let self else { return NSView() }
            return FirstMouseHostingView(rootView: ScreenAnnotateView(
                controller: self,
                surface: self.surface,
                screenSize: screen.frame.size,
                lang: L10n.current
            ))
        }
        overlay.setPassesClicks(false)
        takeTheScreen(true)
        showToolbar()
        HotkeyManager.shared.setDrawingLayerUp(true)
        // Picking a tool IS entering the drawing mode: the arrow at the head of
        // the row is what hands the screen back.
        toolWatch = surface.$tool.dropFirst().sink { [weak self] _ in
            self?.setDrawing(true)
        }
    }

    /// The panel lives in a window of its own, so the mode that lets clicks
    /// through cannot take the panel with it.
    private func showToolbar() {
        guard toolbarWindow == nil else { return }
        let host = FirstMouseHostingView(rootView: ScreenAnnotateToolbar(controller: self,
                                                                 surface: surface,
                                                                 lang: L10n.current))
        let window = MarkupToolbarWindow(content: host)
        toolbarWindow = window
        place(window, on: CaptureController.screenUnderPointer())
        window.orderFrontRegardless()
    }

    /// Where the panel starts out. SPEC: docs/spec.md — the markup toolbar.
    func place(_ window: NSWindow, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let size = window.frame.size
        let inset: CGFloat = 28
        let frame = screen.visibleFrame
        let spot = edge == .top
            ? NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - inset)
            : NSPoint(x: frame.midX - size.width / 2, y: frame.minY + inset)
        window.setFrameOrigin(within(spot, size: size))
    }

    func settleToolbar() {
        guard let window = toolbarWindow,
              let screen = window.screen ?? NSScreen.main else { return }
        edge = window.frame.midY > screen.frame.midY ? .top : .bottom
        window.setFrameOrigin(within(window.frame.origin, size: window.frame.size))
    }

    /// SPEC: docs/spec.md — whole, and off the edges of its screen.
    private func within(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let centre = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(centre) }
            ?? toolbarWindow?.screen ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return origin }
        let margin: CGFloat = 20
        return NSPoint(x: held(origin.x, span: size.width, from: frame.minX, to: frame.maxX, margin: margin),
                       y: held(origin.y, span: size.height, from: frame.minY, to: frame.maxY, margin: margin))
    }

    private func held(_ value: CGFloat, span: CGFloat, from: CGFloat, to: CGFloat, margin: CGFloat) -> CGFloat {
        let least = from + margin, most = to - span - margin
        guard least <= most else { return from + (to - from - span) / 2 }
        return min(max(value, least), most)
    }

    func setDrawing(_ drawing: Bool) {
        isDrawing = drawing
        overlay.setPassesClicks(!drawing)
        takeTheScreen(drawing)
    }

    /// SPEC: docs/spec.md — "Draw over the screen", the key for the mode.
    func togglePassing() {
        guard isUp else { return }
        setDrawing(!isDrawing)
    }

    /// The mode key as it is written on screen; nil while none is set.
    var passCombo: String? {
        HotkeyManager.shared.combo(for: ModuleCatalog.annotatePassAction)?.display
    }

    /// SPEC: docs/spec.md — the Dock lights its icons under a pointer that
    /// never reaches it, so while the drawing has the screen it is not there.
    private func takeTheScreen(_ whole: Bool) {
        guard NSApp != nil else { return }
        if whole {
            NSApp.activate(ignoringOtherApps: true)
            overlay.makeKey(on: CaptureController.screenUnderPointer())
            NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        } else if !NSApp.presentationOptions.isEmpty {
            NSApp.presentationOptions = []
        }
    }

    func clear() {
        surface.clear()
    }

    func exit() {
        HotkeyManager.shared.setDrawingLayerUp(false)
        takeTheScreen(false)
        toolWatch = nil
        surface.stop()
        surface.clear()
        overlay.hide()
        toolbarWindow?.orderOut(nil)
        toolbarWindow?.contentView = nil
        toolbarWindow = nil
        isUp = false
    }

    /// The screen with the drawing on it, minus the toolbar: the marks are
    /// already on screen, so they are captured with everything else.
    func picture() async -> CGImage? {
        guard let screen = CaptureController.screenUnderPointer() else { return nil }
        // The panel steps out of the shot; the marks stay, they are the point.
        toolbarWindow?.orderOut(nil)
        defer { toolbarWindow?.orderFrontRegardless() }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            let id = CaptureController.displayID(of: screen)
            guard let display = content.displays.first(where: { $0.displayID == id })
                    ?? content.displays.first else { return nil }

            let configuration = SCStreamConfiguration()
            configuration.width = Int(Double(display.width) * screen.backingScaleFactor)
            configuration.height = Int(Double(display.height) * screen.backingScaleFactor)
            configuration.showsCursor = false
            return try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: []),
                configuration: configuration
            )
        } catch {
            return nil
        }
    }

    /// SPEC: docs/spec.md — "Saying where the picture went".
    func save(over spot: CGRect) {
        Task { [weak self] in
            guard let self, let picture = await self.picture() else { return }
            let format = UserDefaults.standard.string(forKey: MarkupSettings.formatKey) ?? "png"
            guard let url = MarkupExport.save(picture, format: format) else { return }
            let lang = L10n.current
            MarkupNote.show(L10n.t(.mkSaved, lang) + " · " + url.lastPathComponent,
                            detail: url.deletingLastPathComponent().lastPathComponent
                                + " · " + L10n.t(.convReveal, lang),
                            file: url, over: spot)
        }
    }

    func copyToClipboard() {
        Task { [weak self] in
            guard let self, let picture = await self.picture() else { return }
            MarkupExport.copy(picture)
        }
    }
}

struct ScreenAnnotateView: View {
    @ObservedObject var controller: ScreenAnnotateController
    @ObservedObject var surface: MarkupSurface
    let screenSize: CGSize
    let lang: AppLanguage

    var body: some View {
        ZStack(alignment: .top) {
            MarkupCanvas(surface: surface, background: nil, scale: 1)
                .frame(width: screenSize.width, height: screenSize.height)
                .allowsHitTesting(controller.isDrawing)

            if controller.isDrawing {
                Rectangle()
                    .strokeBorder(Theme.accentYellow.opacity(0.72), lineWidth: 3)
                    .frame(width: screenSize.width, height: screenSize.height)
                    .allowsHitTesting(false)

                Text(tag)
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.86))
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(
                        UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9)
                            .fill(Theme.accentYellow.opacity(0.94))
                    )
                    .allowsHitTesting(false)
            }

        }
        .frame(width: screenSize.width, height: screenSize.height)
    }

    /// SPEC: docs/spec.md — the tag carries the mode key.
    private var tag: String {
        let on = L10n.t(.annotateDrawingOn, lang)
        guard let combo = controller.passCombo else { return on }
        return "\(on) · \(combo) \(L10n.t(.annotateClickMode, lang))"
    }
}

/// The panel of the drawing layer, in its own window: the mode switch, the
/// tools, and what to do with the result.
struct ScreenAnnotateToolbar: View {
    @ObservedObject var controller: ScreenAnnotateController
    @ObservedObject var surface: MarkupSurface
    let lang: AppLanguage

    @State private var copied = false
    @State private var whereCopy: (() -> CGRect)?
    @State private var whereSave: (() -> CGRect)?

    var body: some View {
        MarkupToolbar(surface: surface,
                      tools: ScreenAnnotateController.tools,
                      edge: $controller.edge,
                      lang: lang,
                      toolsActive: controller.isDrawing,
                      trailing: AnyView(actions),
                      leading: AnyView(cursorButton))
            .padding(6)
            .background(MarkupKeys(surface: surface, tools: ScreenAnnotateController.tools))
            .background(WindowDragArea { controller.settleToolbar() })
    }

    private var actions: some View {
        Group {
            if controller.edge.isVertical {
                VStack(spacing: 4) { buttons }
            } else {
                HStack(spacing: 4) { buttons }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button { surface.undo() } label: {
            MarkupIcon(glyph: .undo)
                .foregroundStyle(surface.canUndo ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .markupTip(L10n.t(.mkUndo, lang) + "\n" + L10n.t(.mkDoUndo, lang))

        Button { surface.redo() } label: {
            MarkupIcon(glyph: .redo)
                .foregroundStyle(surface.canRedo ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .markupTip(L10n.t(.mkRedo, lang) + "\n" + L10n.t(.mkDoRedo, lang))

        Button { surface.clear() } label: {
            MarkupIcon(glyph: .clear)
                .foregroundStyle(surface.shapes.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .markupTip(L10n.t(.annotateClear, lang) + "\n" + L10n.t(.mkDoClear, lang))

        Button {
            controller.copyToClipboard()
            copied = true
            if let whereCopy { MarkupNote.show(L10n.t(.clipboardCopied, lang), over: whereCopy()) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { copied = false }
        } label: {
            MarkupIcon(glyph: copied ? .done : .copy)
                .foregroundStyle(copied ? Theme.accentGreen : Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 7).fill(copied ? Theme.chipBg : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .markupAnchor { whereCopy = $0 }
        .markupTip(L10n.t(.copyLabel, lang) + "\n" + L10n.t(.mkDoCopy, lang))

        Button { controller.save(over: whereSave?() ?? .zero) } label: {
            MarkupIcon(glyph: .save)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .markupAnchor { whereSave = $0 }
        .markupTip(L10n.t(.featureSave, lang) + "\n" + L10n.t(.mkDoSave, lang))
        action(.close, .annotateExit) { controller.exit() }
    }

    /// Not the select tool: this hands the SCREEN back, and the panel stays
    /// where it is. Its glyph says so — a pointer with the way past it open.
    private var cursorButton: some View {
        Button {
            controller.setDrawing(false)
        } label: {
            MarkupIcon(glyph: .passThrough)
                .foregroundStyle(controller.isDrawing ? Theme.textSecondary : Theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(controller.isDrawing ? Color.clear : Theme.chipBg)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .markupTip(cursorTip)
    }

    /// SPEC: docs/spec.md — the hint carries the mode key too.
    private var cursorTip: String {
        let head = L10n.t(.annotateClickMode, lang) + "\n" + L10n.t(.mkDoCursor, lang)
        guard let combo = controller.passCombo else { return head }
        return head + "\n" + combo
    }

    private func action(_ glyph: MarkupGlyph, _ name: L10nKey, _ about: L10nKey? = nil,
                        run: @escaping () -> Void) -> some View {
        Button(action: run) {
            MarkupIcon(glyph: glyph)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .markupTip(L10n.t(name, lang) + (about.map { "\n" + L10n.t($0, lang) } ?? ""))
    }
}
