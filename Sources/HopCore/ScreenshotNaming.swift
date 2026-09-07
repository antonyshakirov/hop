import Foundation

/// Names for saved captures: readable, sortable, and never overwriting a shot
/// taken a moment earlier.
/// Tests: Tests/HopCoreTests/ScreenshotNamingTests.swift
public enum ScreenshotNaming {
    public static func fileName(at date: Date, calendar: Calendar, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm"
        return "shot \(formatter.string(from: date)).\(format)"
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
