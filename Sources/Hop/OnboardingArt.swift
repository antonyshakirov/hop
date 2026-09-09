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

/// The screenshot: the capture overlay as it really looks — the screen veiled
/// except for what is being taken — and beside it what came out, marked up.
struct ShotArt: View {
    /// The chosen region, in the miniature screen's own points.
    private static let pick = CGRect(x: 10, y: 32, width: 104, height: 54)

    var body: some View {
        HStack(spacing: 8) {
            capture
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            result
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelBackground)
        // A picture of a screen, not a line of text: mirroring it would leave
        // every `offset` behind and take the composition apart.
        .environment(\.layoutDirection, .leftToRight)
    }

    private var capture: some View {
        ZStack(alignment: .topLeading) {
            screenBehind
            veil
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1)
                .frame(width: Self.pick.width + 2, height: Self.pick.height + 2)
                .position(x: Self.pick.midX, y: Self.pick.midY)
            Circle()
                .fill(Color.white)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 1))
                .frame(width: 6, height: 6)
                .position(x: Self.pick.minX, y: Self.pick.minY)
            Text("1240 × 644")
                .font(Theme.mono(7))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.8)))
                .fixedSize()
                .position(x: Self.pick.maxX + 14, y: Self.pick.maxY + 12)
        }
        .frame(width: 172, height: 116)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.divider, lineWidth: 1))
    }

    /// A window with something in it, so the frame is seen to take one thing
    /// rather than an arbitrary rectangle of grey.
    private var screenBehind: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Theme.glyphInk.opacity(0.18)).frame(width: 3, height: 3)
                }
                MarkupArtBar(width: 42, dim: true)
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 8)
            .frame(height: 18)

            VStack(alignment: .leading, spacing: 5) {
                MarkupArtBar(width: 68)
                MarkupArtBar(width: 52)
                MarkupArtBar(width: 60)
                MarkupArtBar(width: 44)
            }
            .padding(8)
            .frame(width: Self.pick.width, height: Self.pick.height, alignment: .topLeading)
            .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 4))
            .offset(x: Self.pick.minX, y: Self.pick.minY)

            VStack(alignment: .leading, spacing: 5) {
                MarkupArtBar(width: 46, dim: true)
                MarkupArtBar(width: 34, dim: true)
                MarkupArtBar(width: 40, dim: true)
            }
            .offset(x: 118, y: 38)

            VStack(alignment: .leading, spacing: 5) {
                MarkupArtBar(width: 78, dim: true)
                MarkupArtBar(width: 58, dim: true)
            }
            .offset(x: 10, y: 96)
        }
    }

    /// The same veil the picker draws: everything but the chosen pixels.
    private var veil: some View {
        Color.black.opacity(0.24)
            .mask {
                Rectangle()
                    .overlay {
                        Rectangle()
                            .frame(width: Self.pick.width, height: Self.pick.height)
                            .position(x: Self.pick.midX, y: Self.pick.midY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
    }

    /// What came out of the frame: four tools on it, each lying on the line it
    /// is there to mark, each in an ink the toolbar offers.
    private var result: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 11) {
                MarkupArtBar(width: 88)
                MarkupArtBar(width: 70)
                MarkupArtBar(width: 78)
                MarkupArtBar(width: 62, dim: true)
                MarkupArtBar(width: 84, dim: true)
                MarkupArtBar(width: 56, dim: true)
            }
            .padding(.horizontal, 11)
            .padding(.top, 20)

            Capsule()
                .fill(Theme.accentYellow.opacity(0.42))
                .frame(width: 92, height: 10)
                .offset(x: 9, y: 17)

            Ellipse()
                .strokeBorder(Theme.accentGreen, lineWidth: 1.6)
                .frame(width: 78, height: 20)
                .offset(x: 7, y: 28)

            MarkupArtArrow()
                .stroke(Theme.accentRed, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: 28, height: 22)
                .offset(x: 90, y: 32)

            ArtStep(number: "1")
                .offset(x: 78, y: 60)
        }
        .frame(width: 142, height: 116, alignment: .topLeading)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.divider, lineWidth: 1))
    }
}

/// The drawing layer: every display gets its own border and its own tag, and
/// the marks lie on the screen as it stands. Two displays, because that is what
/// the line beside this picture promises.
struct AnnotateArt: View {
    let lang: AppLanguage

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            display(width: 200, height: 116) {
                VStack(alignment: .leading, spacing: 7) {
                    MarkupArtBar(width: 128)
                    MarkupArtBar(width: 96)
                    MarkupArtBar(width: 112)
                    MarkupArtBar(width: 72, dim: true)
                    MarkupArtBar(width: 104, dim: true)
                    MarkupArtBar(width: 84, dim: true)
                }
                .padding(.horizontal, 14)
                .padding(.top, 34)

                Ellipse()
                    .strokeBorder(Theme.accentRed, lineWidth: 1.6)
                    .frame(width: 106, height: 22)
                    .offset(x: 9, y: 36)
                MarkupArtArrow()
                    .stroke(Theme.accentRed, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 32, height: 24)
                    .offset(x: 88, y: 49)
                ArtStep(number: "1")
                    .offset(x: 130, y: 54)
            }

            display(width: 132, height: 92) {
                VStack(alignment: .leading, spacing: 6) {
                    MarkupArtBar(width: 96)
                    MarkupArtBar(width: 74)
                    MarkupArtBar(width: 84)
                    MarkupArtBar(width: 62, dim: true)
                    MarkupArtBar(width: 88, dim: true)
                }
                .padding(.horizontal, 11)
                .padding(.top, 30)

                Capsule()
                    .fill(Theme.accentGreen.opacity(0.45))
                    .frame(width: 90, height: 10)
                    .offset(x: 9, y: 27)
                ArtMagnifier()
                    .offset(x: 56, y: 48)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelBackground)
        // See ShotArt: the offsets here draw a screen, and a mirrored screen is
        // not what either display shows.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func display<Content: View>(width: CGFloat, height: CGFloat,
                                        @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            content()
            Text(L10n.t(.annotateDrawingOn, lang))
                .font(Theme.mono(6.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.black.opacity(0.86))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5)
                        .fill(Theme.accentYellow.opacity(0.94))
                )
                .frame(width: width, alignment: .center)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(Theme.accentYellow.opacity(0.72), lineWidth: 2))
    }
}

/// The counter tool: marks numbered in the order they were made.
private struct ArtStep: View {
    let number: String

    var body: some View {
        Text(number)
            .font(Theme.mono(7.5, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 15, height: 15)
            .background(Theme.accentBlue, in: Circle())
    }
}

/// The loupe: a ring holding what is under it, drawn larger.
private struct ArtMagnifier: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(Theme.glyphInk.opacity(0.42)).frame(width: 30, height: 6)
            Capsule().fill(Theme.glyphInk.opacity(0.42)).frame(width: 20, height: 6)
        }
        .frame(width: 34, height: 34)
        .background(Theme.fieldBg, in: Circle())
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
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
