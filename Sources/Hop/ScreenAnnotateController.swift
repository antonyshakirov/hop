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
        isUp = false
    }

    /// The screen with the drawing on it, minus the toolbar: the marks are
    /// already on screen, so they are captured with everything else.
    func picture() async -> CGImage? {
        guard let screen = CaptureController.screenUnderPointer() else { return nil }
        overlay.setPassesClicks(true)
        defer { overlay.setPassesClicks(!isDrawing) }

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

            MarkupToolbarLayer(surface: surface,
                               tools: ScreenAnnotateController.tools,
                               edge: $controller.edge,
                               size: screenSize,
                               lang: lang,
                               trailing: AnyView(actions))
                .opacity(controller.isDrawing ? 1 : 0.72)
                .frame(width: screenSize.width, height: screenSize.height)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .background(MarkupKeys(surface: surface, tools: ScreenAnnotateController.tools))
    }

    private var actions: some View {
        HStack(spacing: 4) {
            modeSwitch
            Rectangle().fill(Theme.divider).frame(width: 1, height: 20)
            action(.clear) { surface.clear() }
            action(.copy) { controller.copyToClipboard() }
            action(.save) { controller.save() }
            action(.close) { controller.exit() }
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 3) {
            modeButton(drawing: false, glyph: .cursor)
            modeButton(drawing: true, glyph: .pencil)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.fieldBg))
    }

    private func modeButton(drawing: Bool, glyph: MarkupGlyph) -> some View {
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
        }
        .buttonStyle(.plain)
    }

    private func action(_ glyph: MarkupGlyph, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            MarkupIcon(glyph: glyph)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }
}
