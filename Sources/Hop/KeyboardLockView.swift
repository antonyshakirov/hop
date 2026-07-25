import SwiftUI

/// Keyboard-lock module: three durations and one button that locks or unlocks.
/// Deliberately two short lines — it is a one-gesture module, not a panel.
struct KeyboardLockView: View {
    @ObservedObject var lock: KeyboardLockController
    let lang: AppLanguage
    /// The panel closes on lock — the cover takes over from there.
    var closePanel: () -> Void = {}

    @AppStorage(KeyboardLockController.durationKey) private var duration = 60

    var body: some View {
        // Two short lines rather than one: the module name plus three chips plus
        // a button does not fit a single row in a long language, and a truncated
        // module name reads as a bug.
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 12))
                    .foregroundStyle(lock.isLocked ? Theme.editing : Theme.textSecondary)
                Text(L10n.t(.keylockLabel, lang))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                ForEach(KeyboardLockController.durations, id: \.self) { seconds in
                    durationChip(seconds)
                }
            }
            HStack(spacing: 8) {
                Button {
                    if lock.isLocked {
                        lock.unlock()
                    } else {
                        closePanel()
                        lock.lock()
                    }
                } label: {
                    Text(L10n.t(lock.isLocked ? .keylockStop : .keylockStart, lang))
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(Theme.playFg)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
                Spacer(minLength: 0)
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
                } else if lock.isLocked, let remaining = lock.remaining {
                    Text(timeText(remaining))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.editing)
                        .monospacedDigit()
                }
            }
        }
    }

    /// How long cleaning mode lasts before it lets go by itself. The cover's
    /// button and this row both unlock at any moment — the timer is the safety
    /// net, not the only exit.
    private func durationChip(_ seconds: Int) -> some View {
        let active = seconds == duration
        return Button {
            duration = seconds
        } label: {
            Text(label(seconds))
                .font(Theme.mono(9))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(active ? Theme.chipBg : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(4)
    }

    /// "30s" / "1m" / "5m" — the unit letters come from the app's own short
    /// labels so they stay readable in every language.
    private func label(_ seconds: Int) -> String {
        seconds < 60
            ? "\(seconds)\(L10n.t(.keylockSecondsUnit, lang))"
            : "\(seconds / 60)\(L10n.t(.minUnit, lang))"
    }

    private func timeText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
