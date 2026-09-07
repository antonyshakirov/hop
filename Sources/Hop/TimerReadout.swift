import HopCore
import SwiftUI

/// The digits, and the only thing on the panel that moves every second. The
/// panel is one view, so a tick reaching it rebuilds every module in it to shift
/// two figures — these watch the clock themselves instead.
/// SPEC: docs/spec.md — "What a running clock costs".
struct TimerReadout: View {
    @ObservedObject var engine: TimerEngine
    /// The stopwatch counts up; the countdown's own display always counts down.
    let usesElapsed: Bool
    let style: String
    let cell: CGFloat
    let textSize: CGFloat
    let unitsSize: CGFloat
    let highlight: Range<Int>?
    let lang: AppLanguage

    /// The calm pulse a finished, acknowledged clock keeps.
    static let settledDim: Double = 0.4

    private var seconds: TimeInterval {
        usesElapsed && engine.isStopwatch ? engine.elapsed : engine.remaining
    }

    private var text: String { TimeFormatting.display(seconds) }

    private var finished: Bool { engine.state == .finished }

    private var blinkOff: Bool {
        guard finished else { return false }
        guard engine.isFinishBlinking else { return false }
        return Int(engine.heartbeat.timeIntervalSinceReferenceDate * 2) % 2 != 0
    }

    private var pulseOpacity: Double {
        guard engine.isFinishSettled else { return 1 }
        let lit = Int(engine.heartbeat.timeIntervalSinceReferenceDate * 2) % 2 == 0
        return lit ? 1 : Self.settledDim
    }

    private func unitsString(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded(.up)))
        let hours = total / 3600
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)\(L10n.t(.unitHour, lang))") }
        parts.append(String(format: "%02d%@", (total % 3600) / 60, L10n.t(.unitMin, lang)))
        parts.append(String(format: "%02d%@", total % 60, L10n.t(.unitSec, lang)))
        return parts.joined(separator: " ")
    }

    /// What the digits say right now — on the digits themselves, so a tooltip
    /// never reports the second the panel was last rebuilt on.
    private var help: String {
        if usesElapsed, engine.isStopwatch {
            return "\(L10n.t(.stopwatchLabel, lang)) — \(TimeFormatting.display(engine.elapsed))"
        }
        let shown = engine.isStopwatch ? engine.elapsed : engine.remaining
        return L10n.t(.tipDigits, lang)
            .replacingOccurrences(of: "{n}", with: TimeFormatting.display(shown))
    }

    var body: some View {
        digits
            .opacity(pulseOpacity)
            .animation(.easeInOut(duration: 0.28), value: pulseOpacity)
            .help(help)
    }

    @ViewBuilder
    private var digits: some View {
        switch style {
        case "text":
            Text(text)
                .font(Theme.mono(textSize, weight: .semibold))
                .foregroundStyle(blinkOff ? Theme.dotOff : Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case "units":
            Text(unitsString(seconds))
                .font(Theme.mono(unitsSize, weight: .semibold))
                .foregroundStyle(blinkOff ? Theme.dotOff : Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        default:
            DotMatrixDisplay(
                text: text,
                dimCount: finished ? 0 : TimeFormatting.dimCount(for: text),
                blinkOff: blinkOff,
                cell: cell,
                highlight: highlight
            )
        }
    }
}
