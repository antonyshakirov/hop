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
    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
    private var background: MediaBackground {
        if backgroundMode == 1 { return .color(NSColor(color).cgColor) }
        if backgroundMode == 2, let image = backgroundImage { return .image(image) }
        return .transparent
    }

    var body: some View {
        Group {
            if Snapshot.active { content }
            else { ScrollView { content } }
        }.id(model.themeVersion).frame(width: 700).background(Theme.panelBackground).hopLayoutDirection()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(t(.mediaTitle)).font(Theme.mono(16, weight: .semibold))
                Spacer()
                action(t(.convClear)) { controller.clear() }.disabled(controller.locked)
            }
            HStack(spacing: 10) {
                chip(t(.mediaRemove), controller.operation == .background) { controller.operation = .background }
                chip(t(.mediaUpscale), controller.operation == .upscale) { controller.operation = .upscale }
            }.disabled(controller.locked)
            if controller.operation == .upscale { modelRow }
            DropPlate(targeted: targeted, help: t(.mediaDrop), browse: openFiles) {
                Text(t(.mediaDrop)).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity).frame(height: 54)
            }.disabled(controller.locked)
            .snapshotAwareDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                guard !controller.locked else { return false }
                Task {
                    var urls: [URL] = []
                    for provider in providers {
                        if let url = await loadFileURL(provider) { urls.append(url) }
                    }
                    controller.add(urls)
                }
                return true
            }
            if !controller.items.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    Group {
                        if Snapshot.active { queue }
                        else { ScrollView { queue } }
                    }.frame(width: 180, height: 312, alignment: .top)
                    VStack(alignment: .leading, spacing: 12) {
                        if let item = controller.selectedItem {
                            settings(item)
                            HStack(spacing: 10) {
                                preview(item.original, label: t(.mediaOriginal))
                                preview(item.result, label: t(.mediaResult))
                            }
                            if let error = item.error { note(t(error)) }
                            if item.video {
                                note(controller.operation == .background ? t(.mediaPeopleOnly) : t(.mediaVideoExperimental))
                                if !Snapshot.active {
                                    Slider(value: $controller.previewSecond, in: 0...max(0.01, item.duration - 0.05))
                                        .disabled(controller.locked)
                                }
                            }
                            action(t(.mediaPreview)) { controller.run(preview: true, background: background) }
                                .disabled(controller.locked || (controller.operation == .upscale && !controller.modelReady))
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
            if controller.operation == .background { backgroundRow }
            HStack {
                Text(t(.convDestLabel)).foregroundStyle(Theme.textTertiary)
                action(controller.destination.lastPathComponent, systemImage: "folder") { chooseFolder() }
                Spacer()
            }.font(Theme.mono(10)).disabled(controller.locked)
            if let error = controller.error { note(t(error)) }
            HStack {
                if controller.locked {
                    ProgressView().controlSize(.small)
                    action(t(.quitCancel)) { controller.cancel() }
                } else {
                    Text(t(.mediaLocal)).font(Theme.mono(9)).foregroundStyle(Theme.textTertiary)
                    Spacer()
                    action(t(.mediaExport), systemImage: "square.and.arrow.down") { controller.run(preview: false, background: background) }
                        .disabled(controller.items.isEmpty || (controller.operation == .upscale && !controller.modelReady))
                }
            }
        }
        .padding(20).frame(width: 700).background(Theme.panelBackground)
        .foregroundStyle(Theme.textPrimary).hopLayoutDirection()
        .onChange(of: backgroundMode) { _, _ in controller.invalidate() }
        .onChange(of: color) { _, _ in controller.invalidate() }
    }

    private static func duration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(1, seconds)) ?? "—"
    }

    private var modelRow: some View {
        HStack {
            if #available(macOS 15, *) {
                if controller.modelReady { note("Real-ESRGAN · " + t(.mediaModelReady)) }
                else {
                    action(t(.mediaInstallModel)) { controller.installModel() }.disabled(controller.locked)
                    note(t(.mediaModelDownload))
                }
            } else { note(t(.mediaRequires15)) }
            Spacer()
        }
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(controller.items) { item in queueRow(item) }
        }
    }

    private func queueRow(_ item: MediaController.Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard !controller.locked else { return }
                controller.selected = item.id; controller.previewSecond = 0
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                Text(item.url.lastPathComponent).lineLimit(2).font(Theme.mono(10))
                Text(item.size.text).font(Theme.mono(9)).foregroundStyle(Theme.textTertiary)
                }
            }.buttonStyle(.plain)
                if item.progress > 0 && item.progress < 1 { ProgressView(value: item.progress).tint(Theme.editing) }
                if let error = item.error { note(t(error)) }
                if let url = item.exported {
                    action(t(.convReveal), systemImage: "arrow.up.right") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(controller.selected == item.id ? Theme.hoverBg : Theme.rowBg)
                .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder private func settings(_ item: MediaController.Item) -> some View {
        if controller.operation == .upscale {
            let choices = item.size.choices
            if choices.isEmpty { note(t(.mediaAtMaximum)) }
            else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        ForEach(choices) { choice in
                            chip(choice.label, item.resolution == choice) { controller.setResolution(choice, for: item.id) }
                        }
                    }.disabled(controller.locked)
                    if let size = item.size.output(for: item.resolution) {
                        let even = item.video ? MediaSize(width: size.width / 2 * 2, height: size.height / 2 * 2) : size
                        Text(even.text).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                        note(t(.mediaEstimate) + " · " + ByteCountFormatter.string(fromByteCount: Int64(even.rgbaBytes ?? 0), countStyle: .file)
                             + (item.video ? " / " + t(.mediaFrame) : ""))
                        let seconds = Double(item.size.inferenceTiles(to: size)) * controller.secondsPerTile * (item.video ? max(1, item.duration * item.framesPerSecond) : 1)
                        Text("≈ " + Self.duration(seconds)).font(Theme.mono(9)).foregroundStyle(Theme.textTertiary)
                        if item.video {
                            let bitsPerSecond = Double(even.width * even.height) * max(1, item.framesPerSecond) * 0.12
                            Text("≈ " + ByteCountFormatter.string(fromByteCount: Int64(min(Double(Int64.max / 2), item.duration * bitsPerSecond / 8)), countStyle: .file))
                                .font(Theme.mono(9)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
        } else if !item.video, !item.subjects.isEmpty {
            HStack(spacing: 5) {
                chip(t(.mediaAllSubjects), item.subject == 0) { controller.setSubject(0, for: item.id) }
                ForEach(item.subjects, id: \.self) { id in
                    chip("\(id)", item.subject == id) { controller.setSubject(id, for: item.id) }
                }
            }.disabled(controller.locked)
        }
    }

    private var backgroundRow: some View {
        HStack(spacing: 6) {
            Text(t(.mediaBackground)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
            chip(t(.mediaTransparent), backgroundMode == 0) { backgroundMode = 0 }
            chip(t(.mediaColor), backgroundMode == 1) { backgroundMode = 1 }
            if backgroundMode == 1, !Snapshot.active { ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden().frame(width: 30) }
            chip(t(.mediaPicture), backgroundMode == 2) { chooseBackground() }
            Spacer()
            Text(backgroundMode == 0 ? "PNG · MOV α" : "PNG · MP4").font(Theme.mono(9)).foregroundStyle(Theme.textTertiary)
        }.disabled(controller.locked)
    }

    private func preview(_ image: NSImage?, label: String) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Canvas { context, size in
                    for y in stride(from: 0, to: size.height, by: 12) {
                        for x in stride(from: 0, to: size.width, by: 12) {
                            let dark = (Int(x / 12) + Int(y / 12)).isMultiple(of: 2)
                            context.fill(Path(CGRect(x: x, y: y, width: 12, height: 12)), with: .color(dark ? Theme.chipBg : Theme.fieldBg))
                        }
                    }
                }
                if let image { Image(nsImage: image).resizable().scaledToFit() }
            }.frame(height: 178).clipShape(RoundedRectangle(cornerRadius: 7))
            Text(label).font(Theme.mono(9)).foregroundStyle(Theme.textTertiary)
        }.frame(maxWidth: .infinity)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Theme.mono(9)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
    }
    private func action(_ label: String, systemImage: String? = nil, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                Text(label)
            }.font(Theme.mono(10)).padding(.horizontal, 8).padding(.vertical, 6)
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
