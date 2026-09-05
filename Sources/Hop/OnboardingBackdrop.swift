import SwiftUI

/// The onboarding's backdrop, tick-driven at 12fps (this codebase uses no
/// `repeatForever`). SPEC: docs/spec.md — "Onboarding".
struct OnboardingBackdrop: View {
    /// Where the light gathers, in unit coordinates.
    var focus: UnitPoint = UnitPoint(x: 0.5, y: 0.3)

    private let spacing: CGFloat = 26
    private let dot: CGFloat = 2.8

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let centre = CGPoint(x: size.width * focus.x, y: size.height * focus.y)
                let reach = max(size.width, size.height) * 0.62
                let base = Theme.isDark ? 0.30 : 0.22
                let ink = Theme.isDark ? Color.white : Color.black

                var y = spacing / 2
                while y < size.height {
                    var x = spacing / 2
                    while x < size.width {
                        let phase = (x + y) / 260 - t / 4.5
                        let counter = (x - y) / 420 + t / 9
                        let wave = (sin(phase) + sin(counter)) / 2
                        let pull = max(0, 1 - hypot(x - centre.x, y - centre.y) / reach)
                        let alpha = base * (0.35 + 0.65 * pull) * (0.55 + 0.45 * wave)
                        if alpha > 0.012 {
                            let d = dot * (0.8 + 0.35 * wave)
                            context.fill(
                                Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)),
                                with: .color(ink.opacity(alpha))
                            )
                        }
                        x += spacing
                    }
                    y += spacing
                }
            }
        }
        .allowsHitTesting(false)
    }
}
