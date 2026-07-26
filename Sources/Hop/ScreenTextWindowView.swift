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
                    Label(t(.ocrRead), systemImage: "camera.viewfinder")
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
            if Snapshot.active {
                Text(reader.recognized)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.listText)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                    .padding(8)
                    .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 8))
            } else {
                TextEditor(text: Binding(
                    get: { reader.recognized },
                    set: { reader.editRecognized($0) }))
                    .font(Theme.mono(11))
                    .scrollContentBackground(.hidden)
                    .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 8))
                    .frame(minHeight: 160)
            }
            HStack(spacing: 10) {
                Text(t(.ocrWindowInHistory))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
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
                        .foregroundStyle(copied ? Theme.accentGreen : Theme.playFg)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(copied ? Theme.chipBg : Theme.playBg,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
            }
        }
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
