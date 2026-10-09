import AppKit
import HopCore
import SwiftUI
import UniformTypeIdentifiers

struct MediaWindowView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: MediaController
    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"
    @State private var targeted = false
    @State private var backgroundMode = 0
    @State private var color = Color.white
    @State private var backgroundImage: CGImage?
    @State private var quality = 70
    @State private var compressed = false
    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
    private var background: MediaBackground {
        if backgroundMode == 1 { return .color(NSColor(color).cgColor) }
        if backgroundMode == 2, let image = backgroundImage { return .image(image) }
        return .transparent
    }
    private var canExport: Bool {
        !controller.scopedItems.isEmpty && !controller.locked && (controller.operation != .upscale || controller.modelReady)
    }
    private var scopeLabel: String {
        t(.mediaSelectedFiles).replacingOccurrences(of: "{count}", with: String(controller.scopedItems.count))
    }

    var body: some View {
        Group {
            if Snapshot.active { content }
            else { ScrollView { content } }
        }
        .id(model.themeVersion).frame(width: 700)
        .background(Theme.panelBackground).hopLayoutDirection()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t(controller.operation.titleKey)).font(Theme.mono(16, weight: .semibold))
                Spacer()
                action(t(.convClear)) { controller.clear() }.disabled(controller.locked)
            }
            if controller.operation == .upscale, !controller.modelReady { modelRow }
            dropPlate
            if !controller.items.isEmpty {
                HStack(spacing: 8) {
                    chip(t(.uninstallSelectAll), controller.allFilesSelected) { controller.selectAllFiles() }
                    Text(scopeLabel).foregroundStyle(controller.selection.isEmpty ? Theme.textTertiary : Theme.editing)
                    Spacer()
                    Text(t(.mediaIndividualSizes)).foregroundStyle(Theme.textTertiary)
                }.font(Theme.mono(10)).disabled(controller.locked)
                if controller.operation == .upscale { sizeControls }
                else { backgroundRow }
                Group {
                    if Snapshot.active { rows }
                    else { ScrollView { rows }.frame(height: min(220, CGFloat(controller.items.count) * 58 - 1)) }
                }
                if controller.items.contains(where: \.video) {
                    note(t(controller.operation == .upscale ? .mediaVideoExperimental : .mediaPeopleOnly))
                }
            } else if controller.operation == .background { backgroundRow }
            HStack(spacing: 6) {
                Text(t(.convDestLabel)).foregroundStyle(Theme.textTertiary)
                action(controller.destination.lastPathComponent, systemImage: "folder") { chooseFolder() }
                Spacer()
            }.font(Theme.mono(10)).disabled(controller.locked)
            if let error = controller.error { note(t(error)) }
            footer
        }
        .padding(20).frame(width: 700).background(Theme.panelBackground)
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { model.mediaContentHeights[controller.operation] = geo.size.height }
                .onChange(of: geo.size.height) { _, height in model.mediaContentHeights[controller.operation] = height }
        })
        .foregroundStyle(Theme.textPrimary).hopLayoutDirection()
        .onChange(of: backgroundMode) { _, _ in controller.invalidate() }
        .onChange(of: color) { _, _ in controller.invalidate() }
    }

    private var dropPlate: some View {
        DropPlate(targeted: targeted, help: t(.mediaDrop), browse: openFiles) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc").font(.system(size: 20))
                Text(t(.mediaDrop)).font(Theme.mono(11))
            }
            .foregroundStyle(targeted ? Theme.editing : Theme.textTertiary)
            .frame(maxWidth: .infinity).frame(height: 160)
        }.disabled(controller.locked)
        .snapshotAwareDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard !controller.locked else { return false }
            Task {
                var urls: [URL] = []
                for provider in providers { if let url = await loadFileURL(provider) { urls.append(url) } }
                controller.add(urls)
            }
            return true
        }
    }

    private var sizeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(t(.convScaleLabel)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                ForEach(controller.commonResolutions) { choice in
                    chip(choice.label, controller.scopedItems.allSatisfy { $0.resolution == choice }) {
                        controller.applyResolution(choice)
                    }
                }
                if controller.commonResolutions.isEmpty, !controller.scopedItems.isEmpty { note(t(.mediaAtMaximum)) }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text(t(.mediaExportMode)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                chip(t(.mediaFullQuality), !compressed) { compressed = false }
                chip(t(.mediaCompression), compressed) { compressed = true }
                Spacer()
                if controller.scopedItems.contains(where: \.hasTransparency) { note(t(.mediaTransparencyKept)) }
            }
            if compressed {
                HStack(spacing: 8) {
                    Text(t(.convQualityLabel)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                    MiniSlider(value: $quality, range: 1...100, width: 100)
                    Spacer()
                }
            }
        }.disabled(controller.locked)
        .onChange(of: compressed) { _, _ in controller.invalidate() }
        .onChange(of: quality) { _, _ in controller.invalidate() }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(controller.items) { item in
                fileRow(item)
                if item.id != controller.items.last?.id { Divider().overlay(Theme.divider) }
            }
        }
    }

    private func fileRow(_ item: MediaController.Item) -> some View {
        HStack(spacing: 10) {
            Button { controller.toggleSelection(item.id) } label: {
                Image(systemName: controller.selection.contains(item.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(controller.selection.contains(item.id) ? Theme.editing : Theme.textTertiary)
                    .font(.system(size: 13)).frame(width: 20, height: 40)
            }.buttonStyle(.plain).help(item.url.lastPathComponent).disabled(controller.locked)
            ZStack(alignment: .bottomTrailing) {
                if let image = item.original { Image(nsImage: image).resizable().scaledToFit() }
                else { Image(systemName: item.video ? "film" : "photo").foregroundStyle(Theme.textTertiary) }
                if item.video { Image(systemName: "play.fill").font(.system(size: 7)).padding(3).background(Theme.rowBg) }
            }.frame(width: 40, height: 40).background(Theme.rowBg).clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent).font(Theme.mono(11)).lineLimit(1).truncationMode(.middle)
                if let error = item.error { note(t(error)).lineLimit(1) }
                else if item.progress > 0 && item.progress < 1 {
                    ProgressView(value: item.progress).tint(Theme.editing).frame(maxWidth: 180)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text(dimensions(item)).font(Theme.mono(9)).foregroundStyle(Theme.textSecondary)
                Text(bytes(item.sourceBytes) + " → " + bytes(item.outputBytes))
                    .font(Theme.mono(9)).foregroundStyle(Theme.textTertiary)
            }.fixedSize()
            if let url = item.exported {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accentGreen)
                        .frame(width: 24, height: 40)
                }.buttonStyle(.plain).help(t(.convReveal))
            }
        }.padding(.vertical, 8)
    }

    private func bytes(_ count: Int64?) -> String {
        guard let count else { return "—" }
        return ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private func dimensions(_ item: MediaController.Item) -> String {
        let output = controller.operation == .upscale ? item.size.output(for: item.resolution) : item.size
        guard let output else { return item.size.text + " → —" }
        let actual = item.video ? MediaSize(width: output.width / 2 * 2, height: output.height / 2 * 2) : output
        return item.size.text + " → " + actual.text
    }

    private var footer: some View {
        Group {
            if controller.locked {
                HStack { ProgressView().controlSize(.small); Spacer(); action(t(.quitCancel)) { controller.cancel() } }
            } else if controller.operation == .upscale {
                HStack {
                    Spacer()
                    action(t(.mediaExport), systemImage: "square.and.arrow.down") {
                        controller.export(quality: compressed ? .compressed(quality) : .full, background: background)
                    }.disabled(!canExport)
                }
            } else {
                HStack {
                    Text(t(.mediaLocal)).font(Theme.mono(9)).foregroundStyle(Theme.textTertiary)
                    Spacer()
                    action(t(.mediaExport), systemImage: "square.and.arrow.down") {
                        controller.export(quality: .full, background: background)
                    }.disabled(!canExport)
                }
            }
        }
    }

    private var modelRow: some View {
        HStack {
            if #available(macOS 15, *) {
                action(t(.mediaInstallModel)) { controller.installModel() }.disabled(controller.locked)
                note(t(.mediaModelDownload))
            } else { note(t(.mediaRequires15)) }
            Spacer()
        }
    }

    private var backgroundRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(t(.mediaBackground)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                chip(t(.mediaTransparent), backgroundMode == 0) { backgroundMode = 0 }
                chip(t(.mediaColor), backgroundMode == 1) { backgroundMode = 1 }
                chip(t(.mediaPicture), backgroundMode == 2) { chooseBackground() }
                Spacer()
            }
            if backgroundMode == 1, !Snapshot.active {
                HStack(spacing: 12) {
                    Text(t(.mediaColor)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                    ColorPicker(t(.mediaColor), selection: $color, supportsOpacity: false)
                        .labelsHidden().frame(width: 40)
                    Spacer()
                }
            }
        }.disabled(controller.locked)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Theme.mono(9)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
    }
    private func action(_ label: String, systemImage: String? = nil, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 5) { if let systemImage { Image(systemName: systemImage) }; Text(label) }
                .font(Theme.mono(10)).padding(.horizontal, 8).padding(.vertical, 6)
                .background(Theme.chipBg).clipShape(RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }
    private func chip(_ label: String, _ selected: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(label).font(Theme.mono(10)).padding(.horizontal, 7).padding(.vertical, 6)
                .foregroundStyle(selected ? Theme.editing : Theme.textSecondary)
                .background(selected ? Theme.editing.opacity(0.12) : Theme.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }
    private func openFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .movie]
        if panel.runModal() == .OK { controller.add(panel.urls) }
    }
    private func loadFileURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                else { continuation.resume(returning: item as? URL) }
            }
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { controller.destination = url }
    }
    private func chooseBackground() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url, let image = try? MediaImageEngine.read(url) {
            backgroundImage = image; backgroundMode = 2; controller.invalidate()
        }
    }
}
