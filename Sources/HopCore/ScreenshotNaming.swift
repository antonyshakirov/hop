import Foundation

/// Where saved captures go and what they are called: readable, sortable, and
/// never overwriting a shot taken a moment earlier.
/// Tests: Tests/HopCoreTests/ScreenshotNamingTests.swift
public enum ScreenshotNaming {
    /// Where a shot is written: a chosen folder, else the desktop, else home.
    /// SPEC: docs/spec.md — "Screenshot".
    public static func folder(stored: String?, desktop: URL?, home: URL) -> URL {
        if let stored, !stored.isEmpty { return URL(fileURLWithPath: stored) }
        return desktop ?? home
    }

    public static func fileName(at date: Date, calendar: Calendar, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm"
        return "shot \(formatter.string(from: date)).\(format)"
    }

    /// A name typed by hand, made into a file name inside the folder: nil when
    /// nothing usable is left, so the caller falls back to the dated one.
    /// SPEC: docs/spec.md — "Screenshot", the name field.
    public static func cleaned(_ typed: String, format: String) -> String? {
        let parts = typed.components(separatedBy: CharacterSet(charactersIn: "/:"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.allSatisfy { $0 == "." } }
        var stem = parts.joined(separator: "-")
        while stem.hasPrefix(".") { stem.removeFirst() }
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty else { return nil }

        let wanted = format.lowercased()
        let accepted: Set<String> = wanted == "jpg" || wanted == "jpeg" ? ["jpg", "jpeg"] : [wanted]
        let ext = URL(fileURLWithPath: stem).pathExtension.lowercased()
        return accepted.contains(ext) ? stem : "\(stem).\(format)"
    }

    public static func unique(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }

        let url = URL(fileURLWithPath: name)
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            if !taken.contains(candidate) { return candidate }
            counter += 1
        }
    }
}
