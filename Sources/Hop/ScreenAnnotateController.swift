import AppKit
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
        .pencil, .fadingInk, .marker, .arrow, .line,
        .rectangle, .oval, .steps, .text, .eraser,
    ]

    private let overlay = MarkupOverlayController()
    private var toolbarWindow: MarkupToolbarWindow?

    func toggle() {
        isUp ? exit() : show()
    }

    func show() {
        guard !isUp, !Snapshot.active else { return }
        isUp = true
        isDrawing = true
        overlay.show { [weak self] screen in
            guard let self else { return NSView() }
            return NSHostingView(rootView: ScreenAnnotateView(
                controller: self,
                surface: self.surface,
                screenSize: screen.frame.size,
                lang: L10n.current
            ))
        }
        overlay.setPassesClicks(false)
        showToolbar()
    }

    /// The panel lives in a window of its own, so the mode that lets clicks
    /// through cannot take the panel with it.
    private func showToolbar() {
        guard toolbarWindow == nil else { return }
        let host = NSHostingView(rootView: ScreenAnnotateToolbar(controller: self,
                                                                 surface: surface,
                                                                 lang: L10n.current))
        let window = MarkupToolbarWindow(content: host)
        toolbarWindow = window
        place(window, on: CaptureController.screenUnderPointer())
        window.orderFrontRegardless()
    }

    /// Along its edge the panel keeps where it was left; across it, a fixed
    /// distance from the border.
    func place(_ window: NSWindow, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let size = window.frame.size
        let inset: CGFloat = 28
        let frame = screen.frame
        let spot: NSPoint
        switch edge {
        case .top:
            spot = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - inset)
        case .bottom:
            spot = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + inset)
        case .leading:
            spot = NSPoint(x: frame.minX + inset, y: frame.midY - size.height / 2)
        case .trailing:
            spot = NSPoint(x: frame.maxX - size.width - inset, y: frame.midY - size.height / 2)
        }
        window.setFrameOrigin(spot)
    }

    /// Dragging moves the window itself; on release it takes the nearest edge
    /// and turns with it.
    func dragToolbar(by translation: CGSize) {
        guard let window = toolbarWindow else { return }
        let origin = window.frame.origin
        window.setFrameOrigin(NSPoint(x: origin.x + translation.width,
                                      y: origin.y - translation.height))
    }

    func settleToolbar() {
        guard let window = toolbarWindow,
              let screen = window.screen ?? NSScreen.main else { return }
        let centre = CGPoint(x: window.frame.midX - screen.frame.minX,
                             y: screen.frame.maxY - window.frame.midY)
        edge = MarkupToolbar.Edge.nearest(to: centre, in: screen.frame.size)
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.toolbarWindow else { return }
            window.setContentSize(window.contentView?.fittingSize ?? window.frame.size)
            self.place(window, on: screen)
        }
    }

    func setDrawing(_ drawing: Bool) {
        isDrawing = drawing
        overlay.setPassesClicks(!drawing)
    }

    func clear() {
        surface.clear()
    }

    func exit() {
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

    func save() {
        Task { [weak self] in
            guard let self, let picture = await self.picture() else { return }
            let format = UserDefaults.standard.string(forKey: MarkupSettings.formatKey) ?? "png"
            _ = MarkupExport.save(picture, format: format)
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

                Text(L10n.t(.annotateDrawingOn, lang))
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
}

/// The panel of the drawing layer, in its own window: the mode switch, the
/// tools, and what to do with the result.
struct ScreenAnnotateToolbar: View {
    @ObservedObject var controller: ScreenAnnotateController
    @ObservedObject var surface: MarkupSurface
    let lang: AppLanguage

    var body: some View {
        MarkupToolbar(surface: surface,
                      tools: ScreenAnnotateController.tools,
                      edge: $controller.edge,
                      lang: lang,
                      trailing: AnyView(actions))
            .padding(6)
            .background(MarkupKeys(surface: surface, tools: ScreenAnnotateController.tools))
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in controller.dragToolbar(by: value.translation) }
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
        modeSwitch
        Rectangle().fill(Theme.divider)
            .frame(width: controller.edge.isVertical ? 20 : 1,
                   height: controller.edge.isVertical ? 1 : 20)
        action(.clear, .annotateClear) { surface.clear() }
        action(.copy, .copyLabel) { controller.copyToClipboard() }
        action(.save, .featureSave) { controller.save() }
        action(.close, .annotateExit) { controller.exit() }
    }

    private var modeSwitch: some View {
        Group {
            if controller.edge.isVertical {
                VStack(spacing: 3) { modeButtons }
            } else {
                HStack(spacing: 3) { modeButtons }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.fieldBg))
    }

    @ViewBuilder
    private var modeButtons: some View {
        modeButton(drawing: false, glyph: .cursor, name: .annotateClickMode)
        modeButton(drawing: true, glyph: .pencil, name: .annotateDrawMode)
    }

    private func modeButton(drawing: Bool, glyph: MarkupGlyph, name: L10nKey) -> some View {
        let chosen = controller.isDrawing == drawing
        return Button {
            controller.setDrawing(drawing)
        } label: {
            MarkupIcon(glyph: glyph)
                .foregroundStyle(chosen ? (drawing ? Color.black : Theme.textPrimary) : Theme.textSecondary)
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(chosen ? (drawing ? Theme.accentYellow.opacity(0.92) : Theme.chipBg) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.t(name, lang))
    }

    private func action(_ glyph: MarkupGlyph, _ name: L10nKey, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            MarkupIcon(glyph: glyph)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.t(name, lang))
    }
}
