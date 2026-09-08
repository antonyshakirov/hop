import SwiftUI

/// Pictures for the two modules whose panel row shows nothing worth looking at:
/// a field of text you have to read, and a line of durations.
/// SPEC: docs/spec.md — "Onboarding", the module preview.

/// Recognition: a picture with a frame drawn across part of it, and the lines
/// that came out of the frame beside it.
struct ScreenTextArt: View {
    let lang: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            picture
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            lines
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelBackground)
    }

    private var picture: some View {
        VStack(alignment: .leading, spacing: 6) {
            bar(width: 54, dim: true)
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    bar(width: 76)
                    bar(width: 62)
                    bar(width: 48)
                }
                .padding(5)
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Theme.accentYellow,
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 88, height: 34)
            }
            bar(width: 40, dim: true)
        }
        .padding(8)
        .frame(width: 112, alignment: .leading)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.divider, lineWidth: 1))
    }

    private func bar(width: CGFloat, dim: Bool = false) -> some View {
        Capsule()
            .fill(Theme.glyphInk.opacity(dim ? 0.12 : 0.3))
            .frame(width: width, height: 4)
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(L10n.t(.onbSampleOcr, lang)
                .split(separator: "\n").enumerated()), id: \.offset) { _, line in
                Text(String(line))
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.listText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Cleaning mode: the keys, with a lock over them.
struct KeyboardLockArt: View {
    let lang: AppLanguage

    /// A whole keyboard rather than three rows of letters: the modifier keys
    /// and a space bar with something on either side of it are what makes the
    /// shape read as a keyboard.
    private static let rows: [[(String, CGFloat)]] = [
        [("esc", 1.4)] + "QWERTYUIOP".map { (String($0), 1) },
        [("tab", 1.6)] + "ASDFGHJKL".map { (String($0), 1) } + [("↩", 1.6)],
        [("⇧", 2)] + "ZXCVBNM".map { (String($0), 1) } + [("⇧", 1.8)],
        [("fn", 1), ("⌃", 1), ("⌥", 1), ("⌘", 1.4), ("", 4.6), ("⌘", 1.4), ("⌥", 1)],
    ]
    private static let key: CGFloat = 20
    private static let gap: CGFloat = 3

    var body: some View {
        ZStack {
            VStack(spacing: Self.gap) {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Self.gap) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                            cap(item.0, width: item.1)
                        }
                    }
                }
            }
            .opacity(0.8)
            VStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accentYellow)
                Text(L10n.t(.keylockLabel, lang))
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.divider, lineWidth: 1))
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Theme.panelBackground)
    }

    private func cap(_ letter: String, width: CGFloat) -> some View {
        Text(letter)
            .font(Theme.mono(7.5, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .frame(width: Self.key * width + Self.gap * (width - 1), height: 18)
            .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 3.5))
            .overlay(RoundedRectangle(cornerRadius: 3.5).stroke(Theme.divider, lineWidth: 1))
    }
}

/// The screenshot: a frame drawn over part of the screen, and what came out of
/// it — the same picture with a mark on it.
struct ShotArt: View {
    let lang: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            screen
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            result
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelBackground)
    }

    private var screen: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 5) {
                MarkupArtBar(width: 80)
                MarkupArtBar(width: 62)
                MarkupArtBar(width: 72)
                MarkupArtBar(width: 48, dim: true)
                MarkupArtBar(width: 58, dim: true)
            }
            .padding(8)
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Theme.accentYellow, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: 92, height: 40)
                .offset(x: 6, y: 6)
        }
        .frame(width: 122, height: 76, alignment: .topLeading)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.divider, lineWidth: 1))
    }

    private var result: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 5) {
                MarkupArtBar(width: 52)
                MarkupArtBar(width: 40)
            }
            .padding(8)
            MarkupArtArrow()
                .stroke(Theme.accentRed, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: 30, height: 20)
                .offset(x: 16, y: 10)
        }
        .frame(width: 92, height: 56, alignment: .topLeading)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.divider, lineWidth: 1))
    }
}

/// The drawing layer: the screen as it is, with the yellow border of the mode
/// around it and marks lying on top of what is already there.
struct AnnotateArt: View {
    let lang: AppLanguage

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                MarkupArtBar(width: 96)
                MarkupArtBar(width: 72)
                MarkupArtBar(width: 84)
                MarkupArtBar(width: 56, dim: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(width: 148, alignment: .leading)

            Ellipse()
                .strokeBorder(Theme.accentRed, lineWidth: 1.6)
                .frame(width: 62, height: 22)
                .offset(x: -18, y: 22)
            MarkupArtArrow()
                .stroke(Theme.accentRed, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: 32, height: 20)
                .offset(x: 40, y: 40)

            Text(L10n.t(.annotateDrawingOn, lang))
                .font(Theme.mono(6.5, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.86))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                        .fill(Theme.accentYellow.opacity(0.94))
                )
        }
        .frame(width: 148, height: 76)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(Theme.accentYellow.opacity(0.72), lineWidth: 2))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelBackground)
    }
}

/// A line of text as this drawing means it.
private struct MarkupArtBar: View {
    let width: CGFloat
    var dim = false

    var body: some View {
        Capsule()
            .fill(Theme.glyphInk.opacity(dim ? 0.12 : 0.3))
            .frame(width: width, height: 4)
    }
}

/// A hand-drawn arrow, the mark both modules are reached for.
private struct MarkupArtArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tip = CGPoint(x: rect.minX, y: rect.maxY)
        let tail = CGPoint(x: rect.maxX, y: rect.minY)
        path.move(to: tail)
        path.addQuadCurve(to: tip, control: CGPoint(x: rect.midX + rect.width * 0.15,
                                                    y: rect.midY + rect.height * 0.35))
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x + rect.width * 0.30, y: tip.y - rect.height * 0.10))
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x + rect.width * 0.10, y: tip.y - rect.height * 0.34))
        return path
    }
}
