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
    /// The panel folded into a button, for the moments the screen matters more
    /// than the tools. SPEC: docs/spec.md — the markup toolbar.
    @Published private(set) var isFolded = false
    @Published var edge: MarkupToolbar.Edge = .bottom
    let surface = MarkupSurface()

    /// Crop is the one tool that stays out: there is no file to cut. The loupe
    /// and the blur read the streamed screen instead of a captured frame.
    /// SPEC: docs/spec.md — "Draw over the screen".
    static let tools: [MarkupTool] = [
        .select, .pencil, .fadingInk, .marker, .arrow, .line,
        .rectangle, .oval, .steps, .text, .magnifier, .blur, .eraser,
    ]

    let backdrop = LiveScreenBackdrop()
    private let overlay = MarkupOverlayController()
    private var backdropWatch: AnyCancellable?
    private var toolbarWindow: MarkupToolbarWindow?
    private var toolbarHost: NSView?
    private var toolWatch: AnyCancellable?
    private var draggedFrom: (origin: NSPoint, pointer: NSPoint)?

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
                backdrop: self.backdrop,
                screen: screen.frame,
                display: CaptureController.displayID(of: screen),
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
        backdropWatch = surface.objectWillChange
            .throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.refreshBackdrop() }
        refreshBackdrop()
    }

    /// SPEC: docs/spec.md — the loupe and the blur over the live screen.
    private func refreshBackdrop() {
        guard isUp else { return backdrop.stop() }
        let reading: Set<MarkupTool> = [.magnifier, .blur]
        let wanted = reading.contains(surface.tool)
            || surface.shapes.contains { reading.contains($0.tool) }
        guard wanted else { return backdrop.stop() }
        guard CGPreflightScreenCaptureAccess() else {
            backdrop.stop()
            PermissionRepair.askOnce(.screenCapture)
            return
        }
        // Every display the layer covers is streamed, not just the one under
        // the pointer: a blur can be put on any of them, and a canvas with no
        // frame to read hides its regions behind a plate instead.
        backdrop.start(on: NSScreen.screens)
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
        toolbarHost = host
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

    /// WORKAROUND: the gesture's distance comes from a view that travels with
    /// the window; the pointer's place on SCREEN does not.
    /// SPEC: docs/spec.md — the markup toolbar.
    func dragToolbarToPointer() {
        guard let window = toolbarWindow else { return }
        let pointer = NSEvent.mouseLocation
        guard let from = draggedFrom else {
            draggedFrom = (window.frame.origin, pointer)
            return
        }
        let moved = NSPoint(x: from.origin.x + pointer.x - from.pointer.x,
                            y: from.origin.y + pointer.y - from.pointer.y)
        window.setFrameOrigin(within(moved, size: window.frame.size))
    }

    func settleToolbar() {
        draggedFrom = nil
        guard let window = toolbarWindow,
              let screen = window.screen ?? NSScreen.main else { return }
        edge = window.frame.midY > screen.frame.midY ? .top : .bottom
        window.setFrameOrigin(within(window.frame.origin, size: window.frame.size))
    }

    /// SPEC: docs/spec.md — the panel goes anywhere, and stays catchable.
    private func within(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let centre = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(centre) }
            ?? toolbarWindow?.screen ?? NSScreen.main
        guard let frame = screen?.frame else { return origin }
        let caught: CGFloat = 60
        return NSPoint(x: min(max(origin.x, frame.minX - size.width + caught), frame.maxX - caught),
                       y: min(max(origin.y, frame.minY - size.height + caught), frame.maxY - caught))
    }

    func setDrawing(_ drawing: Bool) {
        isDrawing = drawing
        overlay.setPassesClicks(!drawing)
        takeTheScreen(drawing)
    }

    /// SPEC: docs/spec.md — the panel folds into a button.
    func toggleFolded() {
        isFolded.toggle()
        guard let window = toolbarWindow, let host = toolbarHost else { return }
        // The size follows the content, and the content has not been laid out
        // again yet: the window is resized on the next turn of the loop.
        DispatchQueue.main.async {
            let corner = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            window.setContentSize(host.fittingSize)
            window.setFrameOrigin(self.within(NSPoint(x: corner.x, y: corner.y - window.frame.height),
                                              size: window.frame.size))
        }
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
        backdropWatch = nil
        backdrop.stop()
        HotkeyManager.shared.setDrawingLayerUp(false)
        takeTheScreen(false)
        toolWatch = nil
        surface.stop()
        surface.clear()
        overlay.hide()
        toolbarWindow?.orderOut(nil)
        toolbarWindow?.contentView = nil
        toolbarWindow = nil
        toolbarHost = nil
        isFolded = false
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
            // No falling back to whatever display comes first: Save would
            // write a picture of a screen nobody asked for.
            guard let display = content.displays.first(where: { $0.displayID == id })
            else { return nil }

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
            MarkupNote.show(L10n.t(.mkSaved, lang) + " · "
                                + Substitutions.isolate(url.lastPathComponent),
                            detail: Substitutions.isolate(
                                url.deletingLastPathComponent().lastPathComponent)
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
    @ObservedObject var backdrop: LiveScreenBackdrop
    let screen: NSRect
    let display: UInt32
    let lang: AppLanguage

    private var screenSize: CGSize { screen.size }

    /// SPEC: docs/spec.md — each display's layer draws from its own frame.
    private var frame: CGImage? { backdrop.frames[display] }

    var body: some View {
        ZStack(alignment: .top) {
            MarkupCanvas(surface: surface, background: nil, source: live,
                         mosaics: mosaics, scale: 1, display: display)
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

    private var live: Image? {
        guard let frame, screenSize.width > 0 else { return nil }
        return Image(decorative: frame, scale: CGFloat(frame.width) / screenSize.width)
    }

    /// SPEC: docs/spec.md — the blur styles.
    private var mosaics: [Int: Image] {
        guard let frame, screenSize.width > 0 else { return [:] }
        let backing = CGFloat(frame.width) / screenSize.width
        var out: [Int: Image] = [:]
        for shape in surface.visible(on: display) where shape.tool == .blur {
            guard let blur = shape.blur, blur.style == .pixels,
                  out[blur.strength] == nil else { continue }
            let side = Int((MarkupBlur.mosaic(forStrength: blur.strength) * backing).rounded())
            guard let tiles = backdrop.tiled(display: display, side: side) else { continue }
            out[blur.strength] = Image(decorative: tiles, scale: backing)
        }
        return out
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
    /// True once a press on the folded panel has turned into a drag.
    @State private var carried = false
    @State private var whereCopy: (() -> CGRect)?
    @State private var whereSave: (() -> CGRect)?

    var body: some View {
        Group {
            if controller.isFolded { folded } else { full }
        }
        .padding(6)
        .background(MarkupKeys(surface: surface, tools: ScreenAnnotateController.tools))
    }

    /// The panel as a button: the mark, a drag to move it, a click to open it
    /// again. ONE gesture decides which of the two happened — a Button takes
    /// the press before any drag behind it is seen, and the folded panel could
    /// not be moved at all (Anton, 2026-09-09).
    private var folded: some View {
        HopAsterisk(size: 22)
            .frame(width: 46, height: 46)
            .background(
                Circle()
                    .fill(Theme.isDark ? Color(white: 0.086) : Color.white)
                    .overlay(Circle().strokeBorder(Theme.controlStroke.opacity(0.6)))
            )
            .contentShape(Circle())
            .markupTip(L10n.t(.mkUnfold, lang))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if abs(value.translation.width) > 3 || abs(value.translation.height) > 3 {
                            carried = true
                        }
                        if carried { controller.dragToolbarToPointer() }
                    }
                    .onEnded { _ in
                        controller.settleToolbar()
                        if !carried { controller.toggleFolded() }
                        carried = false
                    }
            )
    }

    private var full: some View {
        MarkupToolbar(surface: surface,
                      tools: ScreenAnnotateController.tools,
                      edge: $controller.edge,
                      lang: lang,
                      toolsActive: controller.isDrawing,
                      floating: true,
                      fold: AnyView(foldButton),
                      trailing: AnyView(actions),
                      leading: AnyView(cursorButton))
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { _ in controller.dragToolbarToPointer() }
                    .onEnded { _ in controller.settleToolbar() }
            )
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

        // SPEC: docs/spec.md — the markup toolbar, the rule between the groups.
        Rectangle()
            .fill(Theme.divider)
            .frame(width: controller.edge.isVertical ? 20 : 1,
                   height: controller.edge.isVertical ? 1 : 20)

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

    private var foldButton: some View {
        Button { controller.toggleFolded() } label: {
            MarkupIcon(glyph: .fold)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .markupTip(L10n.t(.mkFold, lang))
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
