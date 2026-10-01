import AppKit
import UniformTypeIdentifiers

/// The app's only Open and Save panels. SPEC: docs/spec.md, "Shared components".
@MainActor
enum FilePicker {
    enum Pick { case files, folders, filesAndFolders }

    /// The chosen URLs; empty when cancelled or under `Snapshot.active`.
    static func open(_ pick: Pick = .files, multiple: Bool = false,
                     types: [UTType] = [], startIn directory: URL? = nil) -> [URL] {
        guard !Snapshot.active else { return [] }
        let panel = NSOpenPanel()
        panel.canChooseFiles = pick != .folders
        panel.canChooseDirectories = pick != .files
        panel.allowsMultipleSelection = multiple
        if !types.isEmpty { panel.allowedContentTypes = types }
        panel.directoryURL = directory
        raise(panel)
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    /// SPEC: docs/spec.md, "Shared components": a picker opens above whatever of Hop's is on screen.
    private static func raise(_ panel: NSSavePanel) {
        let top = NSApp.windows.filter(\.isVisible).map(\.level.rawValue).max() ?? 0
        panel.level = NSWindow.Level(rawValue: max(top + 1, NSWindow.Level.modalPanel.rawValue))
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The chosen destination; nil when cancelled or under `Snapshot.active`.
    static func save(name: String, types: [UTType] = [], startIn directory: URL? = nil) -> URL? {
        guard !Snapshot.active else { return nil }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        if !types.isEmpty { panel.allowedContentTypes = types }
        panel.directoryURL = directory
        raise(panel)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
