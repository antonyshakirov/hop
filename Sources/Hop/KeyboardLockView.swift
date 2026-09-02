import SwiftUI

/// Keyboard-lock module: one line. The durations ARE the button — tapping "5 min"
/// locks for five minutes, the way a timer preset starts the timer (Anton,
/// 2026-07-25). While it runs, the same line shows the countdown and the way out.
struct KeyboardLockView: View {
    @ObservedObject var lock: KeyboardLockController
    let lang: AppLanguage
    /// The panel closes on lock — the cover takes over from there.
    var closePanel: () -> Void = {}

    var body: some View {
        // spacing 6 is the module-row standard: keep-awake, the clipboard and
        // the internet row all sit the same distance from their icon (Anton,
        // 2026-07-26)
        HStack(spacing: 6) {
            ModuleMarkIcon(symbol: "keyboard",
                           color: lock.isLocked ? Theme.editing : Theme.textSecondary)
            Text(L10n.t(.keylockLabel, lang))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                // long module names (ru, de) share the row with three chips —
                // shrinking a hair beats an ellipsis in the middle of a name
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            if lock.needsPermission {
                Button {
                    if let url = URL(string: KeyboardLockController.privacySettingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HoverLabel(text: L10n.t(.ocrOpenSettings, lang), size: 9,
                               color: Theme.accentYellow)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.t(.ocrOpenSettings, lang))
            } else if lock.isLocked {
                if let remaining = lock.remaining {
                    Text(timeText(remaining))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.editing)
                        .monospacedDigit()
                }
                Button {
                    lock.unlock()
                } label: {
                    Text(L10n.t(.keylockStop, lang))
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(Theme.playFg)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
                .help(L10n.t(.keylockStop, lang))
            } else {
                HStack(spacing: 5) {   // the spacing keep-awake's options use
                    ForEach(KeyboardLockController.durations, id: \.self) { seconds in
                        durationChip(seconds)
                    }
                }
            }
        }
    }

    /// A duration locks straight away for that long — there is no separate start
    /// button to press afterwards. Drawn as bare figures, exactly like
    /// keep-awake's: two neighbouring rows of the same shape must not use two
    /// different button styles (Anton, 2026-07-26).
    private func durationChip(_ seconds: Int) -> some View {
        let isInfinity = seconds == 0
        return Button {
            // The panel closes on the LOCK, never on the click. A lock that
            // cannot start has to be able to say so, and there is nowhere to say
            // it from once the panel is gone (Anton, 2026-09-02).
            lock.lock(seconds: seconds) { locked in
                if locked { closePanel() }
            }
        } label: {
            Text(label(seconds))
                .font(Theme.mono(isInfinity ? 15 : 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                // the mono ∞ sits below the optical centre — the same nudge
                // keep-awake's row uses
                .offset(y: isInfinity ? -1 : 0)
                .frame(minWidth: 18)
                .padding(.horizontal, 3)
                .frame(height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(3)
        // a bare figure — and ∞ above all — has to say what it will do
        .help(isInfinity
              ? L10n.t(.tipLockForever, lang)
              : L10n.t(.tipLockFor, lang)
                  .replacingOccurrences(of: "{n}", with: "\(seconds / 60)"))
    }

    /// "1m" / "5m" / "15m", and ∞ for the lock that waits for the button —
    /// the same symbol keep-awake uses for "no limit".
    private func label(_ seconds: Int) -> String {
        seconds == 0 ? "∞" : "\(seconds / 60)\(L10n.t(.minUnit, lang))"
    }

    private func timeText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
