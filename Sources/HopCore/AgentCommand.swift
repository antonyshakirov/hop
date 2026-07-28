import Foundation

/// One instruction handed to Hop from outside — by the user's own AI agent, a
/// shell script, or a Shortcut. Commands arrive as JSON in a file the app
/// watches; the app performs them and empties the file, so "the file is empty
/// again" is the acknowledgement.
///
/// Deliberately a closed list rather than "set any field": an agent asking for
/// `timer.start` is unambiguous, while a declarative "timer: running" leaves the
/// app guessing whether it should restart a timer the user just paused.
public enum AgentCommand: Equatable, Sendable {
    case timerStart(seconds: Int)
    case timerPause
    case timerReset
    case stopwatchStart
    case stopwatchStop
    case trackerStart(task: String)
    case trackerStop
    case todoAdd(TodoDraft)
    case todoComplete(text: String)
    case keepAwake(Bool)

    /// Everything an agent may set on a new to-do in one go.
    public struct TodoDraft: Equatable, Sendable {
        public var text: String
        public var note: String
        public var remindAt: Date?
        public var repeatDays: [Int]
        public var important: Bool

        public init(text: String, note: String = "", remindAt: Date? = nil,
                    repeatDays: [Int] = [], important: Bool = false) {
            self.text = text
            self.note = note
            self.remindAt = remindAt
            self.repeatDays = TodoItem.normalizedWeekdays(repeatDays)
            self.important = important
        }
    }
}

/// Parses the command file. Every rule here is forgiving on purpose: the writer
/// is a language model or a hand-edited file, so one malformed entry must not
/// discard the rest, and an unknown verb must not crash a menu-bar app.
public enum AgentCommandParser {

    /// Commands in file order. Unknown verbs, missing fields and unusable values
    /// are skipped; a file that is not JSON at all yields an empty list.
    public static func parse(_ data: Data) -> [AgentCommand] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let entries: [[String: Any]]
        if let dictionary = root as? [String: Any],
           let list = dictionary["commands"] as? [[String: Any]] {
            entries = list
        } else if let list = root as? [[String: Any]] {
            // a bare array is accepted too — it is what a model writes half the time
            entries = list
        } else {
            return []
        }
        return entries.compactMap(command(from:))
    }

    /// A `hop://` link, which is what a Shortcut (and therefore Siri, in whatever
    /// language the user speaks to it) can open: `hop://timer/start?minutes=16`,
    /// `hop://todo/add?text=call%20the%20notary`. The host and path spell the same
    /// verb the file uses, and the query carries the same fields.
    public static func parse(url: URL) -> AgentCommand? {
        guard url.scheme?.lowercased() == "hop" else { return nil }
        let parts = [url.host ?? ""] + url.path.split(separator: "/").map(String.init)
        var entry: [String: Any] = ["do": parts.filter { !$0.isEmpty }.joined(separator: ".")]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            if let value = item.value { entry[item.name] = value }
        }
        return command(from: entry)
    }

    private static func command(from entry: [String: Any]) -> AgentCommand? {
        // "do" is the documented key; "command" and "action" are accepted because
        // they are the obvious guesses and rejecting them helps nobody.
        let verb = (entry["do"] ?? entry["command"] ?? entry["action"]) as? String
        guard let verb = verb?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }

        switch verb {
        case "timer.start", "timer":
            guard let seconds = seconds(from: entry), seconds > 0 else { return nil }
            return .timerStart(seconds: seconds)
        case "timer.pause": return .timerPause
        case "timer.reset", "timer.stop": return .timerReset
        case "stopwatch.start": return .stopwatchStart
        case "stopwatch.stop": return .stopwatchStop
        case "tracker.start":
            guard let task = nonEmpty(entry["task"] ?? entry["text"]) else { return nil }
            return .trackerStart(task: task)
        case "tracker.stop": return .trackerStop
        case "todo.add", "task.add":
            guard let text = nonEmpty(entry["text"] ?? entry["task"] ?? entry["title"]) else { return nil }
            return .todoAdd(AgentCommand.TodoDraft(
                text: text,
                note: nonEmpty(entry["note"]) ?? "",
                remindAt: date(from: entry["remindAt"] ?? entry["remind_at"] ?? entry["due"]),
                repeatDays: weekdays(from: entry["repeatDays"] ?? entry["repeat_days"]),
                important: boolean(entry["important"])))
        case "todo.complete", "task.complete", "todo.done":
            guard let text = nonEmpty(entry["text"] ?? entry["task"] ?? entry["title"]) else { return nil }
            return .todoComplete(text: text)
        case "keepawake.on", "awake.on": return .keepAwake(true)
        case "keepawake.off", "awake.off": return .keepAwake(false)
        default: return nil
        }
    }

    /// A duration given any of the ways someone would naturally write it.
    private static func seconds(from entry: [String: Any]) -> Int? {
        if let seconds = number(entry["seconds"]) { return seconds }
        if let minutes = number(entry["minutes"]) { return minutes * 60 }
        if let hours = number(entry["hours"]) { return hours * 3600 }
        // "16m", "1h30m", "90s", "25:00"
        if let text = entry["duration"] as? String { return duration(from: text) }
        return nil
    }

    /// `16m`, `1h30m`, `90s`, `25:00`, or a bare number of minutes.
    public static func duration(from text: String) -> Int? {
        let raw = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !raw.isEmpty else { return nil }

        if raw.contains(":") {
            let parts = raw.split(separator: ":").map { Int($0) }
            guard !parts.contains(where: { $0 == nil }) else { return nil }
            let values = parts.compactMap { $0 }
            switch values.count {
            case 2: return values[0] * 60 + values[1]
            case 3: return values[0] * 3600 + values[1] * 60 + values[2]
            default: return nil
            }
        }

        var total = 0
        var current = ""
        var matched = false
        for character in raw {
            if character.isNumber {
                current.append(character)
                continue
            }
            guard let value = Int(current) else { continue }
            switch character {
            case "h": total += value * 3600; matched = true
            case "m": total += value * 60; matched = true
            case "s": total += value; matched = true
            default: break
            }
            current = ""
        }
        if let trailing = Int(current), !trailing.isZero || !matched {
            // a bare number means minutes — "set a timer for 16" is minutes to
            // everyone who says it out loud
            total += matched ? trailing : trailing * 60
            matched = true
        }
        return matched && total > 0 ? total : nil
    }

    /// `true` from JSON, or "true"/"yes"/"1" from a URL query.
    private static func boolean(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        guard let text = (value as? String)?.lowercased() else { return false }
        return ["true", "yes", "1"].contains(text)
    }

    private static func number(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// ISO-8601, with or without the seconds and the zone.
    private static func date(from value: Any?) -> Date? {
        guard let text = nonEmpty(value) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        // a local "2026-07-28 15:00" or "2026-07-28T15:00" reads as this machine's zone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
                       "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// Weekdays as numbers (1 = Sunday) or as names — "mon", "monday", "tue"…
    private static func weekdays(from value: Any?) -> [Int] {
        if let numbers = value as? [Int] { return numbers }
        if let names = value as? [String] {
            return names.compactMap { weekday(named: $0) }
        }
        // a URL query cannot hold an array: "mon,wed" is how it arrives there
        if let list = value as? String {
            return list.split(separator: ",").compactMap { weekday(named: String($0)) }
        }
        return []
    }

    private static func weekday(named raw: String) -> Int? {
        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let number = Int(name) { return number }
        let table = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
        return table[String(name.prefix(3))]
    }
}

private extension Int {
    var isZero: Bool { self == 0 }
}
