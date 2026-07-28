import SwiftUI
import UniformTypeIdentifiers

/// The recognition window: where the text ends up, and the second way to feed
/// the module — drop a picture or paste one (⌘V), instead of framing the screen.
/// Seeing the result matters (Anton, 2026-07-25): a silent copy into the
/// clipboard history left no sign that anything had happened.
struct ScreenTextWindowView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"
    @State private var targeted = false
    @State private var copied = false

    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
    private var reader: ScreenTextController { model.screenText }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.panelBackground)
            .id(model.themeVersion)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            dropZone
            // No result yet → the window is nothing but the plate; the text
            // block (and the extra height for it) appears with the first result.
            if !reader.recognized.isEmpty {
                resultEditor
            }
        }
        .padding(20)
        // The window is exactly as tall as THIS — the padded content, measured
        // before the expanding frame. Measuring after it reads back the window's
        // own height, which is how the plate kept a strip of empty space under
        // it while the margin above stayed 20 (Anton, 2026-07-26).
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { model.screenTextContentHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, height in
                        model.screenTextContentHeight = height
                    }
            }
        )
    }

    /// Both feeds in one place: the crosshair for the screen, the zone for a
    /// picture that already exists.
    private var dropZone: some View {
        VStack(spacing: 8) {
            Text(t(.ocrWindowDrop))
                .font(Theme.mono(11))
                .foregroundStyle(targeted ? Theme.editing : Theme.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button {
                    reader.capture()
                } label: {
                    Label(t(.ocrRead), systemImage: "square.dashed")
                        .font(Theme.mono(10, weight: .bold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(Theme.playFg)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
                .disabled(reader.isBusy)
                Button {
                    reader.recognizeFromPasteboard()
                } label: {
                    Label(t(.ocrPaste), systemImage: "doc.on.clipboard")
                        .font(Theme.mono(10))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
                .disabled(reader.isBusy)
            }
            if let status {
                Text(status)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(targeted ? Theme.editing : Theme.divider,
                              style: StrokeStyle(lineWidth: 1, dash: targeted ? [] : [5, 4]))
        )
        .contentShape(Rectangle())
        .snapshotAwareDrop(of: [.fileURL, .image], isTargeted: $targeted) { providers in
            Task {
                for provider in providers {
                    if let url = await DroppedFiles.url(from: provider) {
                        reader.recognize(imageAt: url)
                        return
                    }
                }
            }
            return true
        }
    }

    /// The text itself, selectable and editable — copy a line or fix a stray
    /// character before taking it somewhere.
    private var resultEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ImageRenderer draws a TextEditor as a yellow "not supported" block,
            // so a render gets the same text as a plain, flat label instead.
            // The two branches must be padded IDENTICALLY: the editor used to
            // carry no inset at all while the render did, so the text sat flush
            // against the field on screen and nobody saw it in a screenshot
            // (Anton, 2026-07-28).
            if Snapshot.active {
                Text(reader.recognized)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.listText)
                    .frame(maxWidth: .infinity, minHeight: 160 - Self.fieldInset * 2,
                           alignment: .topLeading)
                    .padding(Self.fieldInset)
                    .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 8))
            } else {
                TextEditor(text: Binding(
                    get: { reader.recognized },
                    set: { reader.editRecognized($0) }))
                    .font(Theme.mono(11))
                    .scrollContentBackground(.hidden)
                    // safeAreaPadding, NOT padding: padding insets the whole
                    // editor, and the scroll bar goes in with it — a bar that
                    // floats 12pt off the edge of its own field (Anton,
                    // 2026-07-28). This insets the CONTENT and leaves the
                    // editor filling the field, so the bar stays on the edge.
                    // contentMargins was tried first and moved nothing.
                    .safeAreaPadding(Self.fieldInset)
                    .frame(minHeight: 160)
                    .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 10) {
                Text(t(.ocrWindowInHistory))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                // A reading that IS a link is a reading with somewhere to go, so
                // opening it takes the accented slot and copying steps back. The
                // address itself is not repeated on the button: it is already in
                // the field above, in full, which is where it should be read.
                if hasLink {
                    Button {
                        reader.openLink()
                    } label: {
                        Label(t(.ocrOpenLink), systemImage: "arrow.up.right")
                            .font(Theme.mono(10, weight: .bold))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(Theme.playFg)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverDim()
                }
                Button {
                    reader.copyRecognized()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Text(copied ? t(.ocrCopied) : t(.copyLabel))
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(copyForeground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(copied || hasLink ? Theme.chipBg : Theme.playBg,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
            }
        }
    }

    /// Breathing room between the recognized text and the edge of its field.
    /// One constant for both branches — see `resultEditor`.
    private static let fieldInset: CGFloat = 12

    private var hasLink: Bool { reader.link != nil }

    /// Copy keeps the green receipt, gives up the accent when there is a link
    /// beside it, and is the primary button otherwise.
    private var copyForeground: Color {
        if copied { return Theme.accentGreen }
        return hasLink ? Theme.textSecondary : Theme.playFg
    }

    private var status: String? {
        switch reader.state {
        case .idle, .done: return nil
        case .selecting: return t(.ocrSelecting)
        case .reading: return t(.ocrReading)
        case .empty: return t(.ocrNothing)
        case .denied: return t(.ocrNeedsPermission)
        case .failed: return t(.ocrFailed)
        }
    }
}
