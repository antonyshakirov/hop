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
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    /// The chosen destination; nil when cancelled or under `Snapshot.active`.
    static func save(name: String, types: [UTType] = [], startIn directory: URL? = nil) -> URL? {
        guard !Snapshot.active else { return nil }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        if !types.isEmpty { panel.allowedContentTypes = types }
        panel.directoryURL = directory
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
