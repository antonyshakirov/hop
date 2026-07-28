import Foundation
import Vision

/// The recognition languages this machine actually has models for, named the way
/// the app's own language picker names languages: in the language itself, sorted
/// alphabetically by that native name.
///
/// Vision's list is versioned per OS, so it is asked rather than hard-coded — a
/// tag that is not on it makes the whole recognition request fail.
enum ScreenTextLanguages {
    struct Language: Hashable {
        let tag: String     // Vision's own spelling: "ja-JP", "zh-Hans"
        let name: String    // native name, e.g. 日本語
    }

    /// Computed once: `supportedRecognitionLanguages()` builds a request under the
    /// hood, and the settings menu redraws often.
    static let supported: [Language] = {
        let tags = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
        return tags
            .map { Language(tag: $0, name: nativeName(for: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    /// The stored selection: space-separated tags, since @AppStorage cannot hold
    /// an array. Empty = automatic detection.
    static func selected(from stored: String) -> [String] {
        stored.split(separator: " ").map(String.init)
    }

    static func name(for tag: String) -> String? {
        supported.first { $0.tag == tag }?.name
    }

    /// The language's name in itself — `Locale(identifier:)` asked about its own
    /// identifier. Falls back to the raw tag on anything the OS cannot name.
    private static func nativeName(for tag: String) -> String {
        let locale = Locale(identifier: tag)
        guard let name = locale.localizedString(forIdentifier: tag) else { return tag }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
