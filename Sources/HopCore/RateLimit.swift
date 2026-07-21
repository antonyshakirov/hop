import Foundation

/// The display unit for a torrent speed limit. The canonical stored value is
/// always KB/s; the UI can show and accept it as either unit.
public enum RateUnit: String, CaseIterable, Sendable {
    case kb
    case mb
}

/// Torrent speed-limit conversion. Storage is canonical KB/s (0 = unlimited);
/// the UI may display and enter it as KB/s or MB/s. 1 MB = 1000 KB — the same
/// decimal convention the torrent card uses when it prints speeds (bytes ÷ 10^6).
public enum RateLimit {
    public static let kbPerMB = 1000
    /// Upper bound on the canonical KB/s value: MB mode allows up to 9999.9 MB.
    public static let maxKB = 9_999_900

    /// Clamp a canonical KB/s value into the valid range (0…maxKB).
    public static func clampKB(_ kb: Int) -> Int {
        max(0, min(kb, maxKB))
    }

    /// Render a canonical KB/s value in the given unit. KB mode is the integer;
    /// MB mode is one decimal with trailing zeros (and a bare ".0") trimmed —
    /// 2000 → "2", 1500 → "1.5", 500 → "0.5". 0 stays "0" (unlimited) in both.
    public static func display(kb: Int, unit: RateUnit) -> String {
        switch unit {
        case .kb:
            return "\(clampKB(kb))"
        case .mb:
            let mb = Double(clampKB(kb)) / Double(kbPerMB)
            var s = String(format: "%.1f", mb)
            if s.hasSuffix(".0") { s = String(s.dropLast(2)) }
            return s
        }
    }

    /// Parse user input in the given unit into a canonical KB/s value. An empty
    /// string or "0" is 0 (unlimited). KB mode takes digits only; MB mode takes a
    /// decimal (digits with at most one dot). Anything else returns nil (= keep
    /// the current value). The result is clamped to maxKB.
    public static func parse(_ text: String, unit: RateUnit) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        switch unit {
        case .kb:
            guard trimmed.allSatisfy(\.isNumber), let v = Int(trimmed) else { return nil }
            return clampKB(v)
        case .mb:
            let dots = trimmed.filter { $0 == "." }.count
            guard dots <= 1, trimmed.allSatisfy({ $0.isNumber || $0 == "." }),
                  let mb = Double(trimmed), mb >= 0 else { return nil }
            return clampKB(Int((mb * Double(kbPerMB)).rounded()))
        }
    }
}
