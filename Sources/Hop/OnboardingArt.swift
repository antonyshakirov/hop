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

    /// Staggered like a real keyboard: rows of equal length, each starting half
    /// a key further in, so the shape is a keyboard and not a pyramid.
    private static let rows = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
    private static let key: CGFloat = 22
    private static let gap: CGFloat = 4

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: Self.gap) {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: Self.gap) {
                        ForEach(Array(row), id: \.self) { cap(String($0)) }
                    }
                    .padding(.leading, CGFloat(index) * (Self.key + Self.gap) / 2)
                }
                Capsule()
                    .fill(Theme.rowBg)
                    .overlay(Capsule().stroke(Theme.divider, lineWidth: 1))
                    .frame(width: 140, height: 20)
                    .padding(.leading, (Self.key + Self.gap) * 2)
            }
            .opacity(0.7)
            .blur(radius: 1.4)
            Image(systemName: "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.accentYellow)
                .padding(16)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Theme.divider, lineWidth: 1))
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Theme.panelBackground)
    }

    private func cap(_ letter: String) -> some View {
        Text(letter)
            .font(Theme.mono(8, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .frame(width: Self.key, height: 20)
            .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.divider, lineWidth: 1))
    }
}
