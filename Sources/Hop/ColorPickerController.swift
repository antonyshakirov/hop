import AppKit
import HopCore

/// The eyedropper: a hotkey (or the panel button) opens macOS's own loupe,
/// and the pixel you click lands in the clipboard history as a color entry —
/// already on the pasteboard, ready to paste.
///
/// `NSColorSampler` is the system loupe, so this needs NO screen-recording
/// permission and no bitmap of the screen ever reaches us: the OS hands back
/// one color. That is the whole reason the eyedropper is a separate module from
/// text recognition, which does need the permission.
@MainActor
final class ColorPickerController: ObservableObject {
    static let formatKey = "colorFormat"

    /// The loupe is on screen right now. Drives the button's label so the panel
    /// doesn't look idle while the user is aiming.
    @Published private(set) var isSampling = false

    private let clipboard: ClipboardController
    /// One sampler for the app's lifetime: a fresh one per pick leaks the
    /// overlay window if the user dismisses it with Escape.
    private let sampler = NSColorSampler()

    init(clipboard: ClipboardController) {
        self.clipboard = clipboard
    }

    var format: ColorFormat {
        get { ColorFormat(rawValue: UserDefaults.standard.string(forKey: Self.formatKey) ?? "") ?? .hex }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.formatKey) }
    }

    /// Show the loupe. Escape (or clicking outside a screen) hands back nil and
    /// nothing is written — a cancelled pick must not touch the clipboard.
    /// - Parameter onPicked: called after a colour was stored, never on cancel.
    ///   The panel uses it to come back: it had to close for the loupe, and the
    ///   whole point is to see the new colour in the list (Anton, 2026-07-26).
    func pick(onPicked: (() -> Void)? = nil) {
        guard !isSampling, !Snapshot.active else { return }
        isSampling = true
        // The sampler calls back on the main thread but its handler is not typed
        // as main-actor, so state it explicitly instead of hopping through a Task
        // (a hop would let the panel render one frame with a stale "picking…").
        sampler.show { [weak self] color in
            MainActor.assumeIsolated {
                guard let picker = self else { return }
                picker.isSampling = false
                guard let color else { return }
                picker.store(color)
                onPicked?()
            }
        }
    }

    /// Copy ONE notation of a stored colour — the list shows all three and each
    /// is its own button, so the click already says which form is wanted.
    func copy(text: String, hex: String) {
        guard !hex.isEmpty else { return }
        // the colour is already in the history — only the pasteboard changes,
        // so the list keeps the order the colours were picked in
        clipboard.putOnPasteboard(text)
    }

    /// The sampler reports a color in whatever space the screen uses; sRGB is the
    /// space every notation we write out is defined in, so convert before reading
    /// components. A color that refuses to convert is dropped rather than stored
    /// with wrong numbers.
    private func store(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return }
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        clipboard.remember(
            color: ColorFormatting.canonical(r: r, g: g, b: b),
            text: ColorFormatting.string(format, r: r, g: g, b: b))
    }
}
