import Foundation
import HopPluginAPI

enum PluginInstalledQuery {
    static func filter(_ records: [PluginRecord], query: String) -> [PluginRecord] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return records }
        return records.filter { record in
            let manifest = record.package.manifest
            return [manifest.name, manifest.description, manifest.author, manifest.id]
                .contains { $0.localizedStandardContains(query) }
        }
    }
}
