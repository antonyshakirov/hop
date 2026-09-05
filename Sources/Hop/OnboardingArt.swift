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

    /// A whole keyboard rather than three rows of letters: the modifier keys and
    /// a space bar with something on either side of it are what makes the shape
    /// read as a keyboard (Anton, 2026-09-05).
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
