/// Paste-routing policy for the standalone converter window.
///
/// Hop is an accessory (menu-bar) app with no Edit menu, so ⌘V has no Paste
/// key-equivalent and `NSApplication` only offers a key equivalent to its
/// `keyWindow`. When the converter is opened from a background state (the app
/// was not frontmost — e.g. the user copied files in Finder and only then
/// triggered the converter), `NSApp.activate` is asynchronous and, on macOS 14+
/// cooperative activation, may be delayed or denied, so `keyWindow` is nil at
/// the moment ⌘V is pressed and the key equivalent reaches no window at all.
///
/// The window therefore catches ⌘V with a local keyDown monitor, which fires
/// regardless of key-window assignment. This pure gate decides when that
/// monitor should treat ⌘V as a converter paste, so the decision is testable
/// without AppKit.
public enum ConverterPaste {
    /// Whether a ⌘V (or ⌘⇧V) seen by the local monitor should be ingested by
    /// the converter window.
    ///
    /// True only when the converter window is the intended paste target: it is
    /// visible AND either it is already the key window, or nothing has claimed
    /// key yet (activation still settling right after opening from the
    /// background — the state in which the plain key-equivalent route drops the
    /// paste). When another window owns key, ⌘V belongs to that window (e.g. a
    /// text field there) and must NOT be stolen.
    public static func shouldIngest(
        windowVisible: Bool,
        windowIsKey: Bool,
        hasKeyWindow: Bool
    ) -> Bool {
        guard windowVisible else { return false }
        return windowIsKey || !hasKeyWindow
    }
}
