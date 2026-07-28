import SwiftUI

/// Hop chooses its language in its own picker, not through the system locale.
/// SwiftUI derives `layoutDirection` from the process locale, so a user running
/// macOS in English who picks Arabic inside Hop would otherwise get Arabic text
/// in a left-to-right shell. Every window root sets the direction itself.
private struct HopLayoutDirection: ViewModifier {
    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"

    func body(content: Content) -> some View {
        content.environment(
            \.layoutDirection,
            L10n.resolve(languageRaw).isRTL ? .rightToLeft : .leftToRight
        )
    }
}

extension View {
    /// Apply to every window, panel and popover root. Reading the setting through
    /// `@AppStorage` makes the flip follow the picker live, with no restart.
    func hopLayoutDirection() -> some View { modifier(HopLayoutDirection()) }
}

extension NSMenu {
    /// AppKit surfaces do not see the SwiftUI environment, so the right-click
    /// menu is told the direction separately.
    func applyHopLayoutDirection() {
        userInterfaceLayoutDirection = L10n.current.isRTL ? .rightToLeft : .leftToRight
    }
}
