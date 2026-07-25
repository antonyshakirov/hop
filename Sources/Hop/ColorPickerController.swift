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
    func pick() {
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
            }
        }
    }

    /// Rewrite the top color entry into the current notation, so switching the
    /// format is visible immediately (and pastes right) instead of only applying
    /// to the NEXT pick.
    func reformatLatest() {
        guard let latest = clipboard.items.first(where: { $0.colorHex != nil }),
              let hex = latest.colorHex,
              let parts = ColorFormatting.components(hex) else { return }
        clipboard.remember(
            color: hex,
            text: ColorFormatting.string(format, r: parts.r, g: parts.g, b: parts.b))
    }

    /// Put a color from the history back on the pasteboard in the CURRENT
    /// notation — the swatch strip's tap action.
    func copy(hex: String) {
        guard let parts = ColorFormatting.components(hex) else { return }
        clipboard.remember(
            color: hex,
            text: ColorFormatting.string(format, r: parts.r, g: parts.g, b: parts.b))
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
