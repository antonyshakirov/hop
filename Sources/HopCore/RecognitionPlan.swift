import Foundation

/// Which languages text recognition asks Vision for.
///
/// The bug this fixes: the app used to ask for the INTERFACE language plus
/// English and nothing else, so a Japanese or Chinese page was read as if it
/// were Latin — the Mori Art Museum's opening hours came back as `4829 8238(`
/// instead of `森美術館`.
///
/// Measured on macOS 26 (2026-07-28) before choosing this design:
///
/// | image | request `en-US` | request auto-detect |
/// |---|---|---|
/// | Japanese line | garbage, confidence 0.50 | correct, confidence 0.50 |
/// | Chinese line | garbage, confidence **1.00** | correct, confidence 0.50 |
/// | English line | correct, 1.00 | identical, 1.00 |
/// | mixed Russian + English | correct | identical |
///
/// Two conclusions drive the code below. Vision's confidence cannot be used to
/// judge a pass — a wrong-language reading of Chinese reported FULL confidence —
/// so there is no scoring and no "was that any good?" heuristic. And automatic
/// detection never did worse than an explicit list, including on the mixed
/// Latin/Cyrillic screen an earlier comment in this file worried about, so it is
/// the default rather than a fallback.
public enum RecognitionPlan {

    /// The languages to put on the request. A user who picked languages gets
    /// exactly those, mapped onto what this machine supports; picking nothing
    /// leaves it empty, which means "let Vision decide".
    ///
    /// Vision spells its tags "en-US" / "zh-Hans", so the match is by prefix, and
    /// a tag this machine does not list is dropped — an unsupported tag makes the
    /// WHOLE request fail.
    public static func languages(selected: [String], supported: [String]) -> [String] {
        guard !supported.isEmpty else { return [] }
        var out: [String] = []
        for code in selected {
            if let match = supported.first(where: { $0.hasPrefix(code) }), !out.contains(match) {
                out.append(match)
            }
        }
        return out
    }

    /// True when Vision should detect the script itself: nothing was chosen, or
    /// what was chosen does not exist on this machine. An explicit choice turns
    /// detection OFF — `recognitionLanguages` is ignored while it is on, so the
    /// two cannot both apply.
    public static func detectsAutomatically(selected: [String], supported: [String]) -> Bool {
        languages(selected: selected, supported: supported).isEmpty
    }
}
