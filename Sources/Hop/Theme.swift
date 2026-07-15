import SwiftUI

enum Theme {
    static let themeKey = "appTheme" // auto | dark | light
    /// Kept up to date by the system theme change observer.
    static var systemDark = true

    static var isDark: Bool {
        switch UserDefaults.standard.string(forKey: themeKey) ?? "auto" {
        case "dark": return true
        case "light": return false
        default: return systemDark
        }
    }

    static var background: Color { isDark ? Color(white: 0.045) : Color(red: 0.973, green: 0.968, blue: 0.955) } // light theme: warm, near-white
    static var dotBright: Color { isDark ? .white : Color(white: 0.05) }
    static var dotHalo: Color { isDark ? Color.white.opacity(0.16) : .clear } // halos look smeared on light backgrounds
    static var dotDim: Color { isDark ? Color.white.opacity(0.30) : Color.black.opacity(0.27) }
    static var dotOff: Color { isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.022) }
    static var textPrimary: Color { isDark ? Color.white.opacity(0.92) : Color.black.opacity(0.88) }
    static var textSecondary: Color { isDark ? Color.white.opacity(0.66) : Color.black.opacity(0.68) }
    /// Long help text: noticeably lighter than secondary — readable without glare.
    static var docText: Color { isDark ? Color.white.opacity(0.70) : Color.black.opacity(0.75) }
    /// List text (clipboard): gray rows are hard to read in the light theme.
    static var listText: Color { isDark ? Color.white.opacity(0.62) : Color.black.opacity(0.78) }
    static var textTertiary: Color { isDark ? Color.white.opacity(0.44) : Color.black.opacity(0.52) }
    static var controlStroke: Color { isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.28) }
    static var divider: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.1) }

    // fill backgrounds
    static var chipBg: Color { isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.11) }
    static var fieldBg: Color { isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06) }
    static var rowBg: Color { isDark ? Color.white.opacity(0.045) : Color.black.opacity(0.032) }
    static var hoverBg: Color { isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06) }
    static var switchOffBg: Color { isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.15) }
    static var playBg: Color { isDark ? .white : Color(white: 0.1) }
    static var playFg: Color { isDark ? .black : .white }
    /// Accent for "currently editing / awake active" — yellow;
    /// in the light theme it is dark gold (accentYellow adapts on its own).
    static var editing: Color { accentYellow }

    /// Panel background: base color + barely visible grain (film vibe).
    static var panelBackground: some View {
        ZStack {
            background
            NoiseOverlay()
        }
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // Mini toggle in the panel style (the system Toggle does not render in
    // ImageRenderer and clashes with the dark style)
    struct MiniSwitch: View {
        @Binding var isOn: Bool
        var tint: Color = Theme.accentGreen

        var body: some View {
            Button {
                isOn.toggle()
            } label: {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    // both states are the same size (30×18); off = a plain
                    // capsule with no stroke, like the native macOS switch
                    Capsule()
                        .fill(isOn ? tint : Theme.switchOffBg)
                        .frame(width: 30, height: 18)
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .padding(2)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // Hover highlight — applied to every clickable element
    struct HoverHighlight: ViewModifier {
        var cornerRadius: CGFloat = 6
        @State private var hovering = false

        func body(content: Content) -> some View {
            content
                .background(
                    hovering ? Theme.hoverBg : .clear,
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { inside in
                    hovering = inside
                    // anything clickable always signals it with the cursor
                    if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
        }
    }

    // Native Apple system colors
    static let accentBlue = Color(nsColor: .systemBlue)
    static let accentCyan = Color(nsColor: .systemCyan)
    static let accentGreen = Color(nsColor: .systemGreen)
    static var accentYellow: Color {
        // light theme: dark yellow (goldenrod) — readable without turning orange
        isDark ? Color(nsColor: .systemYellow) : Color(red: 0.85, green: 0.53, blue: 0.0) // light: amber, not brown
    }
    static var accentOrange: Color {
        // light: a notch darker than system orange — reads better on the
        // light panel and matches the converter progress row
        isDark ? Color(nsColor: .systemOrange) : Color(red: 0.72, green: 0.38, blue: 0.02)
    }
    static var accentRed: Color {
        // system red glares on a light background — darken it
        isDark ? Color(nsColor: .systemRed) : Color(red: 0.85, green: 0.30, blue: 0.04)
    }
    static let accentPurple = Color(nsColor: .systemPurple)

    /// Second shade for graphs: the same color at a different lightness with
    /// full opacity — both lines carry equal visual weight.
    static func graphShade(_ base: Color) -> Color {
        let ns = NSColor(base)
        let blended = ns.blended(withFraction: isDark ? 0.5 : 0.42,
                                 of: isDark ? .white : .black) ?? ns
        return Color(nsColor: blended)
    }
}

extension View {
    func hoverHighlight(_ cornerRadius: CGFloat = 6) -> some View {
        modifier(Theme.HoverHighlight(cornerRadius: cornerRadius))
    }

    /// Hover without a background — brightness only: no layout shifts, no confused alignment.
    func hoverDim() -> some View {
        modifier(Theme.HoverDim())
    }
}

extension Theme {
    struct HoverDim: ViewModifier {
        @State private var hovering = false

        func body(content: Content) -> some View {
            content
                .opacity(hovering ? 0.65 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { inside in
                    hovering = inside
                    if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
        }
    }
}
