import AppKit
import HopCore
import SwiftUI

/// The background the frame stands on and the air around it, in a popover hung
/// off the toolbar. Off by default, so a plain screenshot stays one keystroke
/// away.
struct FrameDressingPopover: View {
    @ObservedObject var editor: ScreenshotEditor
    var lang: AppLanguage

    var body: some View {
        MarkupPopoverBody {
            switchRow(L10n.t(.dressLabel, lang), size: 12, isOn: Binding(
                get: { editor.dressing.isOn },
                set: { editor.dressing.isOn = $0; editor.refreshPreview() }
            ))

            Group {
                backgrounds
                MarkupStepper(title: L10n.t(.dressPadding, lang), value: $editor.dressing.padding,
                              range: 0...20) { editor.scheduleRefresh() }
                MarkupStepper(title: L10n.t(.dressCorners, lang), value: $editor.dressing.corners,
                              range: 0...20) { editor.scheduleRefresh() }
                MarkupStepper(title: L10n.t(.dressShadow, lang), value: $editor.dressing.shadow,
                              range: 0...20) { editor.scheduleRefresh() }
                if case .picture = editor.dressing.background {
                    MarkupStepper(title: L10n.t(.blurStrength, lang),
                                  value: Binding(
                                    get: { pictureBlur },
                                    set: { setPictureBlur($0) }
                                  ),
                                  range: 0...20) { editor.scheduleRefresh() }
                }

                switchRow(L10n.t(.dressBrowser, lang), size: 11, isOn: Binding(
                    get: { editor.dressing.browserFrame },
                    set: { editor.dressing.browserFrame = $0; editor.refreshPreview() }
                ))

                SteadyField(text: Binding(
                    get: { editor.dressing.address },
                    set: { editor.dressing.address = $0; editor.scheduleRefresh() }
                ), placeholder: L10n.t(.dressAddress, lang))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fieldBg))
                .disabled(!editor.dressing.browserFrame)
                .opacity(editor.dressing.browserFrame ? 1 : 0.35)

                Button(L10n.t(.resetDefaults, lang)) {
                    editor.dressing = .standard
                    editor.dressing.isOn = true
                    editor.refreshPreview()
                }
                .buttonStyle(.plain)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
            }
            .disabled(!editor.dressing.isOn)
            .opacity(editor.dressing.isOn ? 1 : 0.35)
        }
    }

    private var backgrounds: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t(.dressBackground, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
            // Two rows, never a third: the twelve grounds plus the two of
            // one's own are seven and seven.
            HStack(spacing: 7) { swatches(0..<6); ownColourButton }
            HStack(spacing: 7) { swatches(6..<FrameDressingRenderer.presets.count); ownPicture }
        }
    }

    private var ownColourButton: some View {
        Button {
            MarkupColourPanel.shared.show(startingAt: ownColour) { picked in
                editor.dressing.background = .colour(picked.markupHex)
                editor.refreshPreview()
            }
        } label: {
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                      center: .center))
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(
                    Theme.glyphInk.opacity(isOwnColour ? 0.9 : 0.2),
                    lineWidth: isOwnColour ? 2 : 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var ownPicture: some View {
        Button { pickBackground() } label: {
            MarkupIcon(glyph: .picture, size: 15)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.rowBg))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                    Theme.glyphInk.opacity(isPicture ? 0.9 : 0.16),
                    lineWidth: isPicture ? 2 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.t(.markImage, lang))
    }

    private func swatches(_ range: Range<Int>) -> some View {
        ForEach(range, id: \.self) { index in
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

    private var isOwnColour: Bool {
        if case .colour = editor.dressing.background { return true }
        return false
    }

    private var isPicture: Bool {
        if case .picture = editor.dressing.background { return true }
        return false
    }

    private var ownColour: String {
        if case .colour(let hex) = editor.dressing.background { return hex }
        return "#1C1C1E"
    }

    private var pictureBlur: Int {
        if case .picture(_, let blur) = editor.dressing.background { return blur }
        return 0
    }

    private func setPictureBlur(_ blur: Int) {
        guard case .picture(let name, _) = editor.dressing.background else { return }
        editor.dressing.background = .picture(name, blur)
    }

    private func pickBackground() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let name = WatermarkRenderer.store(imageAt: url, called: "backdrop") else { return }
        editor.dressing.background = .picture(name, pictureBlur)
        editor.refreshPreview()
    }

    private func chosen(_ index: Int) -> Bool {
        if case .preset(let current) = editor.dressing.background { return current == index }
        return false
    }
}

/// The mark stamped over the picture: where it sits, how big, how faint, and
/// whether it repeats across the whole frame.
struct WatermarkPopover: View {
    @ObservedObject var editor: ScreenshotEditor
    var lang: AppLanguage

    var body: some View {
        MarkupPopoverBody {
            switchRow(L10n.t(.markLabel, lang), size: 12, isOn: Binding(
                get: { editor.watermark.isOn },
                set: { editor.watermark.isOn = $0; editor.refreshPreview() }
            ))

            Group {
                SteadyField(text: Binding(
                    get: { editor.watermark.text },
                    set: { editor.watermark.text = $0; editor.scheduleRefresh() }
                ), placeholder: L10n.t(.markText, lang))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fieldBg))

                Button(L10n.t(.markImage, lang)) { pickImage() }
                    .buttonStyle(.plain)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)

                MarkupStepper(title: L10n.t(.markOpacity, lang), value: $editor.watermark.opacity,
                              range: 5...100) { editor.scheduleRefresh() }
                MarkupStepper(title: L10n.t(.markSize, lang), value: $editor.watermark.size,
                              range: 1...20) { editor.scheduleRefresh() }
                slants

                switchRow(L10n.t(.markTiled, lang), size: 11, isOn: Binding(
                    get: { editor.watermark.tiled },
                    set: { editor.watermark.tiled = $0; editor.refreshPreview() }
                ))

                if editor.watermark.tiled {
                    MarkupStepper(title: L10n.t(.markSpread, lang), value: $editor.watermark.spread,
                                  range: 10...300) { editor.scheduleRefresh() }
                }

                // A tile covers the whole frame; a corner is meaningless then.
                spots
                    .disabled(editor.watermark.tiled)
                    .opacity(editor.watermark.tiled ? 0.35 : 1)
            }
            .disabled(!editor.watermark.isOn)
            .opacity(editor.watermark.isOn ? 1 : 0.35)
        }
    }

    private var slants: some View {
        HStack(spacing: 6) {
            Text(L10n.t(.markSlant, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 6)
            ForEach([-45, 0, 45], id: \.self) { angle in
                Button {
                    editor.watermark.slant = angle
                    editor.refreshPreview()
                } label: {
                    Text("Aa")
                        .font(Theme.mono(9))
                        .rotationEffect(.degrees(Double(angle)))
                        .frame(width: 34, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(editor.watermark.slant == angle ? Theme.chipBg : Theme.rowBg))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

/// The panel's own switch, at the panel's own size and green. A stock
/// `Toggle(.switch)` next to it is half again as tall.
private func switchRow(_ title: String, size: CGFloat, isOn: Binding<Bool>) -> some View {
    HStack {
        Text(title).font(Theme.mono(size)).foregroundStyle(Theme.textPrimary)
        Spacer(minLength: 8)
        Theme.MiniSwitch(isOn: isOn)
    }
}

/// The shell both popovers share: one width, one padding, and a ceiling on the
/// height so a long panel scrolls instead of running off the screen.
private struct MarkupPopoverBody<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // No ScrollView and nothing hidden behind a switch: an NSPopover keeps
        // the size it was first given, so a panel that grows when something is
        // ticked stays the size of the tick.
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(14)
        .frame(width: 246, alignment: .leading)
        .background(Theme.background)
    }
}

/// A slider that names what it changes and shows the number it is on.
private struct MarkupStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var settled: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("\(value)").font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()); settled() }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
        }
    }
}
