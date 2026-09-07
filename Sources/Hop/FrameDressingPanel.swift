import AppKit
import HopCore
import SwiftUI

/// The editor's left column: the background the frame stands on, the air around
/// it, and the watermark. Off by default, so a plain screenshot stays one
/// keystroke away.
struct FrameDressingPanel: View {
    @ObservedObject var editor: ScreenshotEditor
    var lang: AppLanguage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: Binding(
                    get: { editor.dressing.isOn },
                    set: { editor.dressing.isOn = $0; editor.refreshPreview() }
                )) {
                    Text(L10n.t(.dressLabel, lang)).font(Theme.mono(12))
                }
                .toggleStyle(.switch)

                if editor.dressing.isOn {
                    backgrounds
                    slider(.dressPadding, value: $editor.dressing.padding, range: 0...20)
                    slider(.dressCorners, value: $editor.dressing.corners, range: 0...20)
                    slider(.dressShadow, value: $editor.dressing.shadow, range: 0...20)

                    Toggle(isOn: Binding(
                        get: { editor.dressing.browserFrame },
                        set: { editor.dressing.browserFrame = $0; editor.refreshPreview() }
                    )) {
                        Text(L10n.t(.dressBrowser, lang)).font(Theme.mono(11))
                    }
                    .toggleStyle(.switch)

                    if editor.dressing.browserFrame {
                        TextField(L10n.t(.dressAddress, lang), text: Binding(
                            get: { editor.dressing.address },
                            set: { editor.dressing.address = $0; editor.refreshPreview() }
                        ))
                        .textFieldStyle(.plain)
                        .font(Theme.mono(11))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fieldBg))
                    }

                    Button(L10n.t(.resetDefaults, lang)) {
                        editor.dressing = .standard
                        editor.dressing.isOn = true
                        editor.refreshPreview()
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                }

                Rectangle().fill(Theme.divider).frame(height: 1)

                Toggle(isOn: Binding(
                    get: { editor.watermark.isOn },
                    set: { editor.watermark.isOn = $0; editor.refreshPreview() }
                )) {
                    Text(L10n.t(.markLabel, lang)).font(Theme.mono(12))
                }
                .toggleStyle(.switch)

                if editor.watermark.isOn {
                    TextField(L10n.t(.markText, lang), text: Binding(
                        get: { editor.watermark.text },
                        set: { editor.watermark.text = $0; editor.refreshPreview() }
                    ))
                    .textFieldStyle(.plain)
                    .font(Theme.mono(11))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fieldBg))

                    Button(L10n.t(.markImage, lang)) { pickImage() }
                        .buttonStyle(.plain)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)

                    slider(.markOpacity, value: $editor.watermark.opacity, range: 5...100)
                    slider(.markSize, value: $editor.watermark.size, range: 1...20)
                    spots

                    Toggle(isOn: Binding(
                        get: { editor.watermark.tiled },
                        set: { editor.watermark.tiled = $0; editor.refreshPreview() }
                    )) {
                        Text(L10n.t(.markTiled, lang)).font(Theme.mono(11))
                    }
                    .toggleStyle(.switch)
                }
            }
            .padding(14)
        }
    }

    private var backgrounds: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t(.dressBackground, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
            HStack(spacing: 8) {
                ForEach(0..<FrameDressingRenderer.presets.count, id: \.self) { index in
                    let pair = FrameDressingRenderer.presets[index]
                    Button {
                        editor.dressing.background = .preset(index)
                        editor.refreshPreview()
                    } label: {
                        LinearGradient(colors: [Color(nsColor: pair.0), Color(nsColor: pair.1)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Theme.glyphInk.opacity(chosen(index) ? 0.9 : 0.16),
                                                  lineWidth: chosen(index) ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var spots: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t(.markSpot, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
            HStack(spacing: 6) {
                ForEach(Watermark.Spot.allCases, id: \.self) { spot in
                    Button {
                        editor.watermark.spot = spot
                        editor.refreshPreview()
                    } label: {
                        Text(spotMark(spot))
                            .font(Theme.mono(10))
                            .frame(width: 30, height: 26)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(editor.watermark.spot == spot ? Theme.chipBg : Theme.rowBg))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func slider(_ key: L10nKey, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.t(key, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("\(value.wrappedValue)").font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                onEditingChanged: { editing in if !editing { editor.refreshPreview() } }
            )
        }
    }

    private func chosen(_ index: Int) -> Bool {
        if case .preset(let current) = editor.dressing.background { return current == index }
        return false
    }

    private func spotMark(_ spot: Watermark.Spot) -> String {
        switch spot {
        case .topLeading: return "◤"
        case .topTrailing: return "◥"
        case .bottomLeading: return "◣"
        case .bottomTrailing: return "◢"
        case .centre: return "◈"
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        editor.watermark.imageName = WatermarkRenderer.store(imageAt: url)
        editor.refreshPreview()
    }
}
