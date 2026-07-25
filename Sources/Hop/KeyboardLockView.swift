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
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 12))
                .foregroundStyle(lock.isLocked ? Theme.editing : Theme.textSecondary)
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
            } else {
                ForEach(KeyboardLockController.durations, id: \.self) { seconds in
                    durationChip(seconds)
                }
            }
        }
    }

    /// A duration chip locks straight away for that long — there is no separate
    /// start button to press afterwards.
    private func durationChip(_ seconds: Int) -> some View {
        Button {
            closePanel()
            lock.lock(seconds: seconds)
        } label: {
            Text(label(seconds))
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(5)
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
