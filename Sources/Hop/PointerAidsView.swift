import HopCore
import SwiftUI

/// Draws the presenting pointer over the whole layer: the spotlight first, then
/// the trail, the ring and the clicks.
/// SPEC: docs/spec.md — the presenting pointer.
struct PointerAidsView: View {
    @ObservedObject var pointer: PointerAidsController
    /// The screen this layer covers, in AppKit's own coordinates.
    let screen: NSRect

    var body: some View {
        Canvas { context, size in
            let aids = pointer.aids
            guard aids.isOn else { return }
            let colour = Color(markupHex: aids.hex)
            let here = local(pointer.at, in: size)

            if aids.spotlight {
                let hole = Path(ellipseIn: CGRect(x: here.x - aids.size * 3, y: here.y - aids.size * 3,
                                                  width: aids.size * 6, height: aids.size * 6))
                var veil = Path(CGRect(origin: .zero, size: size))
                veil.addPath(hole)
                context.fill(veil, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
                context.stroke(hole, with: .color(colour.opacity(0.55)), lineWidth: 2)
            }

            if aids.trail {
                for mark in pointer.trail {
                    let strength = PointerAids.fade(age: pointer.now - mark.born,
                                                    life: PointerAids.trailLife)
                    guard strength > 0 else { continue }
                    let point = local(mark.point, in: size)
                    let dot = CGRect(x: point.x - aids.size / 3, y: point.y - aids.size / 3,
                                     width: aids.size / 1.5, height: aids.size / 1.5)
                    context.fill(Path(ellipseIn: dot), with: .color(colour.opacity(0.35 * strength)))
                }
            }

            if aids.ring {
                let ring = CGRect(x: here.x - aids.size, y: here.y - aids.size,
                                  width: aids.size * 2, height: aids.size * 2)
                context.fill(Path(ellipseIn: ring), with: .color(colour.opacity(0.22)))
                context.stroke(Path(ellipseIn: ring), with: .color(colour.opacity(0.85)), lineWidth: 2)
            }

            for click in pointer.clicks {
                let age = pointer.now - click.born
                let strength = PointerAids.fade(age: age, life: PointerAids.clickLife)
                guard strength > 0 else { continue }
                let radius = PointerAids.clickRadius(age: age, from: aids.size)
                let point = local(click.point, in: size)
                let ring = CGRect(x: point.x - radius, y: point.y - radius,
                                  width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: ring), with: .color(colour.opacity(strength)),
                               lineWidth: 3 * strength + 1)
            }
        }
        .allowsHitTesting(false)
    }

    /// AppKit counts from the bottom left of the whole desktop; the canvas
    /// counts from the top left of this screen.
    private func local(_ point: NSPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x - screen.minX, y: size.height - (point.y - screen.minY))
    }
}

/// The presenting pointer's settings, opened from the panel.
struct PointerAidsPopover: View {
    @ObservedObject var pointer: PointerAidsController
    let lang: AppLanguage

    private let palette = ["#FFD60A", "#FF453A", "#32D74B", "#0A84FF", "#FFFFFF"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(L10n.t(.pointerRing, lang), isOn: Binding(
                get: { pointer.aids.ring }, set: { pointer.aids.ring = $0 }))
            row(L10n.t(.pointerSpotlight, lang), isOn: Binding(
                get: { pointer.aids.spotlight }, set: { pointer.aids.spotlight = $0 }))
            row(L10n.t(.pointerTrail, lang), isOn: Binding(
                get: { pointer.aids.trail }, set: { pointer.aids.trail = $0 }))
            row(L10n.t(.pointerClicks, lang), isOn: Binding(
                get: { pointer.aids.clicks }, set: { pointer.aids.clicks = $0 }))

            Rectangle().fill(Theme.divider).frame(height: 1)

            HStack(spacing: 8) {
                ForEach(palette, id: \.self) { hex in
                    Button { pointer.aids.hex = hex } label: {
                        Circle()
                            .fill(Color(markupHex: hex))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(
                                Theme.glyphInk.opacity(pointer.aids.hex == hex ? 0.9 : 0.2),
                                lineWidth: pointer.aids.hex == hex ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Text(L10n.t(.markSize, lang))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textSecondary)
                Slider(value: Binding(get: { pointer.aids.size },
                                      set: { pointer.aids.size = $0 }),
                       in: 14...54)
                    .frame(width: 130)
            }
        }
        .padding(12)
        .frame(width: 230)
        .background(Theme.background)
    }

    private func row(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 12)
            Theme.MiniSwitch(isOn: isOn)
        }
    }
}
